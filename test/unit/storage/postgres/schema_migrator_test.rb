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

      assert_silent do
        subject.migrate! # Nil
        _(subject.current_version).must_equal(1)

        temp = pg_conn.exec("SELECT * FROM dataset")
        _(temp).must_be_instance_of PG::Result

        subject.migrate!(0)
        _(subject.current_version).must_equal(0)
      end
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
end
