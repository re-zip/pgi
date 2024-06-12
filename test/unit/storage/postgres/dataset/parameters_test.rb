require "test/helper"
require "pgi/dataset/query"

describe PGI::Dataset::Parameters do
  subject do
    PGI::Dataset::Parameters
  end

  describe "#length" do
    it "has one thats equal to the input" do
      _(subject.new({ a: 1, b: 2 }).length).must_equal 2
    end
  end
end
