module PGI
  VERSION = File.read("#{__dir__}/../../VERSION").split("\n").first&.freeze
end
