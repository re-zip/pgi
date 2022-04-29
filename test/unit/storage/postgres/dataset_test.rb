require "test/helper"
require "pgi/dataset"

describe PGI::Dataset do
  include PGI::Test::Methods

  let(:pg_conn) { postgres_connection }
  let(:migrator) { postgres_migrator(pg_conn) }
  let(:repo) do
    Class.new do
      extend PGI::Dataset[PG_CONN, :dataset, cursor: nil]

      class << self
        attr_accessor :pg_conn
      end
    end
  end

  before do
    migrator.migrate!(0)
    migrator.migrate!
  end

  describe "#select" do
    it "returns an Query object" do
      _(repo.select(:id).is_a?(PGI::Dataset::Query)).must_equal true
    end

    it "sets a select clause" do
      repo.select(:age, :name).tap do |query|
        _(query.sql).must_match(/SELECT "dataset"\."age", "dataset"\."name" FROM/)
      end
    end
  end

  describe "#where" do
    it "sets a WHERE clause from a Hash param" do
      repo.where(name: "joe", age: 25).tap do |query|
        _(query.sql).must_match(/"dataset"\."name" = \$1 AND "dataset"\."age" = \$2/)
        _(query.params).must_equal ["joe", 25]
      end
    end

    it "handles placesholders in WHERE clause from a String" do
      params = ["joe", 25]
      repo.where("name = ? AND age = ?", params).tap do |obj|
        _(obj.sql).must_match(/WHERE name = \$1 AND age = \$2/)
        _(obj.params).must_equal params
      end

      repo.where("name = $1 AND age = $2", params).tap do |obj|
        _(obj.sql).must_match(/WHERE name = \$1 AND age = \$2/)
        _(obj.params).must_equal params
      end
    end
  end

  describe "#insert" do
    it "inserts data and returns new row" do
      _(repo.insert(name: "jill", age: "25")).must_equal("id" => 2, "name" => "jill", "age" => 25)
      _(repo.find(2)).must_equal("id" => 2, "name" => "jill", "age" => 25)
    end

    it "inserts no data and returns new row with default values" do
      _(repo.insert).must_equal("id" => 2, "name" => nil, "age" => nil)
      _(repo.find(2)).must_equal("id" => 2, "name" => nil, "age" => nil)
    end
  end

  describe "#update" do
    it "updates existing record" do
      _(repo.update(1, age: 26)).must_equal("id" => 1, "name" => "joe", "age" => 26)
      _(repo.find(1)).must_equal("id" => 1, "name" => "joe", "age" => 26)
    end
  end

  describe "#delete" do
    it "deletes specified row" do
      _(repo.delete(1)).must_equal("id" => 1, "name" => "joe", "age" => 25)
      _(repo.find(1)).must_be_nil
    end
  end

  describe "#find" do
    it "returns row if id exist" do
      repo.find(1).tap do |hsh|
        _(hsh).must_equal("id" => 1, "name" => "joe", "age" => 25)
      end
    end

    it "returns nil if no row with id exist" do
      _(repo.find(2)).must_be_nil
    end
  end

  describe "#all" do
    it "returns an array of rows" do
      repo.all.tap do |arr|
        _(arr.is_a?(Array)).must_equal true
        _(arr[0]).must_equal("id" => 1, "name" => "joe", "age" => 25)
      end
    end
  end

  describe "#first" do
    it "returns row if id exist" do
      repo.first.tap do |hsh|
        _(hsh).must_equal("id" => 1, "name" => "joe", "age" => 25)
      end
    end

    it "returns nil if no row with id exist" do
      _(repo.find(2)).must_be_nil
    end
  end

  describe "#last" do
    it "returns row if id exist" do
      repo.last.tap do |hsh|
        _(hsh).must_equal("id" => 1, "name" => "joe", "age" => 25)
      end
    end

    it "returns nil if no row with id exist" do
      _(repo.find(2)).must_be_nil
    end
  end

  describe "#count" do
    it "returns number of rows in table" do
      _(repo.count).must_equal 1
    end
  end

  describe "#page" do
    it "returns number of rows in table" do
      3.times { |x| repo.insert(name: "jimbo", age: 20 + x) }
      _(repo.page(1, 1)).must_equal [{ "id" => 2, "name" => "jimbo", "age" => 20 }]
      _(repo.page(2, 1)).must_equal [{ "id" => 3, "name" => "jimbo", "age" => 21 }]
    end
  end
end
