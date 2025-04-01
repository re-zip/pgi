module PGI
  class SchemaMigrator
    @config     = Struct.new(:pg_conn, :migration_files, :seed_files).new
    @migrations = Hash.new { |h, k| h[k] = {} }.merge(
      # Default migration
      0 => {
        1 => <<~SQL,
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER,
            created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            up TEXT,
            down TEXT
          );
          CREATE TABLE IF NOT EXISTS schema_lock (
            locked_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NULL,
            onerow BOOLEAN PRIMARY KEY DEFAULT TRUE CONSTRAINT onerow_uni CHECK (onerow)
          );
          INSERT INTO schema_lock DEFAULT VALUES ON CONFLICT DO NOTHING;
        SQL
        -1 => <<~SQL,
          DROP TABLE schema_migrations;
          DROP TABLE schema_lock;
        SQL
      },
    )

    def initialize(version)
      raise "FATAL: version must be an integer > 0" unless version.is_a?(Integer) && version.positive?
      raise "FATAL: Duplication migration version" if self.class.migrations.key?(version)
      raise "FATAL: Broken migration ID sequence" unless version == self.class.migrations.keys.max + 1

      @version = version
    end

    def up
      self.class.migrations[@version][1] = yield
    end

    def down
      self.class.migrations[@version][-1] = yield
    end

    class << self
      attr_reader :config, :migrations

      def configure
        yield(config)

        self
      end

      def migrate!(version = nil)
        raise "FATAL: version must be an integer >= 0" unless version.nil? || (version.is_a?(Integer) && version >= 0)

        config.migration_files.sort.each { |file| require file }
        to_version = version || latest_migration.to_i
        fetch_migrations!

        raise "FATAL: Migration version does not exist" unless version.nil? || migrations.key?(version)

        if current_version == to_version
          puts "No migrations detected..."
          return
        end

        puts "Attemping to acquire schema lock"
        schema_lock! do
          puts "Schema lock acquired"
          current = current_version
          if current == to_version
            # :nocov:
            puts "No migrations detected... after schema lock acquired"
            return
            # :nocov:
          end
          walk       = to_version - current
          direction  = walk.positive? ? 1 : -1
          steps      =
            if direction == 1
              migrations.keys[(current + 1)..].to_a
            else
              migrations.keys[0..current].to_a.reverse
            end.take(walk.abs)

          config.pg_conn.transaction do
            steps.each do |v|
              delete_version(v) if direction == -1
              config.pg_conn.exec(migrations[v][direction])
              add_version(v) if direction == 1
            end
          end
        end
      end

      def version(version)
        yield(new(version))
      end

      def current_version
        current = config.pg_conn.exec(<<~SQL).first
          SELECT * FROM schema_migrations
          ORDER BY version DESC LIMIT 1
        SQL

        (current && current["version"].to_i) || 0
      rescue PG::UndefinedTable => e
        raise unless e.message =~ /relation "schema_migrations" does not exist/

        -1
      end

      def destroy!
        config.pg_conn.exec(<<~SQL)
          DO $$ DECLARE
            r RECORD;
          BEGIN
            FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = current_schema() AND tablename != 'spatial_ref_sys') LOOP
              EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
            END LOOP;
            FOR r IN (SELECT DISTINCT typname FROM pg_type INNER JOIN pg_enum ON pg_enum.enumtypid = pg_type.oid) LOOP
              EXECUTE 'DROP TYPE IF EXISTS ' || quote_ident(r.typname) || ' CASCADE';
            END LOOP;
          END $$;
        SQL
      end

      def schema_lock!
        loop do
          success = acquire_lock!
          if success
            yield
            release_lock!
            return
          else
            sleep 1
          end
        end
      end

      def acquire_lock!
        config.pg_conn.exec_params(<<~SQL, []).to_a.length == 1
          UPDATE schema_lock
          SET locked_at = NOW()
          WHERE COALESCE(locked_at, '1970-1-1'::TIMESTAMP WITHOUT TIME ZONE) < NOW() - interval '15 seconds'
          RETURNING *
        SQL
      rescue PG::UndefinedTable => e
        raise unless e.message =~ /relation "schema_lock" does not exist/

        true
      end

      def release_lock!
        config.pg_conn.exec_params(<<~SQL, []).to_a
          UPDATE schema_lock
          SET locked_at = NULL
        SQL
        nil
      rescue PG::UndefinedTable => e
        raise unless e.message =~ /relation "schema_lock" does not exist/

        nil
      end

      private

      def fetch_migrations!
        result = config.pg_conn.exec_params(<<~SQL, [migrations.keys.max]).to_a
          SELECT * from schema_migrations WHERE version > $1
        SQL

        @migrations = migrations.merge(result.to_h do |x|
          [x["version"].to_i, { 1 => x["up"], -1 => x["down"] }]
        end)
      rescue PG::UndefinedTable => e
        raise unless e.message =~ /relation "schema_migrations" does not exist/
      end

      def latest_migration
        migrations.keys.max || -1
      end

      def add_version(version)
        config.pg_conn.exec_params(<<~SQL, [version, migrations[version][1], migrations[version][-1]])
          INSERT INTO schema_migrations
          (version, up, down) VALUES ($1, $2, $3)
        SQL
      end

      def delete_version(version)
        config.pg_conn.exec_params(<<~SQL, [version])
          DELETE FROM schema_migrations
          WHERE version = $1
        SQL
      end
    end
  end
end
