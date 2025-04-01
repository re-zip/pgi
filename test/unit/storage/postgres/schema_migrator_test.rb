require "test/helper"
require "pgi/db"
require "pgi/schema_migrator"

describe PGI::SchemaMigrator do
  include PGI::Test::Methods

  let(:pg_conn) { postgres_connection }

  subject = PGI::SchemaMigrator

  before do
    subject.configure do |config|
      config.migration_files = [File.realpath("test/fixtures/migrations.rb")]
      config.pg_conn = pg_conn
    end
  end

  describe "initialize" do
    it "run migration functions" do
      # Reset to a complety empty database
      subject.migrate!(0)
      pg_conn.exec("DROP TABLE schema_migrations")
      pg_conn.exec("DROP TABLE schema_lock")

      assert_output(/Attemping to acquire schema lock\nSchema lock acquired/) do
        subject.migrate! # Nil
        _(subject.current_version).must_equal(1)

        temp = pg_conn.exec("SELECT * FROM dataset")
        _(temp).must_be_instance_of PG::Result

        subject.migrate!(0)
        _(subject.current_version).must_equal(0)
      end
    end

    it "automatically rollbacks if there is extra migrations in the db" do
      subject.migrate!
      pg_conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS a(b INT8);
        DELETE FROM a;
        INSERT INTO schema_migrations
        (version, created_at, up, down)
        VALUES
        (2, NOW(), '', 'INSERT INTO a (b) VALUES (0)');
      SQL
      subject.migrate!
      result = pg_conn.exec(<<~SQL).to_a.first["b"]
        SELECT * FROM a;
      SQL
      _(result).must_equal 0
      subject.migrations.delete(2)
    end
  end

  describe "migrate! errors" do
    it "puts message if same version detected" do
      assert_output(/No migrations detected...\n/) do
        subject.migrate!(0)
        subject.migrate!(0) # Run twice to make sure it has 0 first
      end
    end

    it "raises exception when version is a string" do
      e = assert_raises RuntimeError do
        subject.migrate!("a")
      end
      _(e.message).must_equal "FATAL: version must be an integer >= 0"
    end

    it "raises exception when version is negative" do
      e = assert_raises RuntimeError do
        subject.migrate!(-9)
      end
      _(e.message).must_equal "FATAL: version must be an integer >= 0"
    end

    it "raises an exception when version doesn't exist" do
      e = assert_raises RuntimeError do
        subject.migrate!(99)
      end
      _(e.message).must_equal "FATAL: Migration version does not exist"
    end
  end

  describe "schema_lock!" do
    it "ensures order" do
      threads = []
      number = 0
      5.times do |i|
        threads.push(Thread.new do
          subject.schema_lock! do
            i = number
            sleep 0.01
            number = i + 1
          end
        end)
      end
      threads.each(&:join)
      _(number).must_equal(5)
    end

    it "doesnt break if schema_lock table isnt there" do
      pg_conn.exec("DROP TABLE schema_lock")
      a = 0
      subject.schema_lock! do
        a = 1
      end
      _(a).must_equal 1
      pg_conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS schema_lock (
          locked_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NULL,
          onerow BOOLEAN PRIMARY KEY DEFAULT TRUE CONSTRAINT onerow_uni CHECK (onerow)
        );
        INSERT INTO schema_lock DEFAULT VALUES ON CONFLICT DO NOTHING;
      SQL
    end
  end
end
