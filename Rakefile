APP_ROOT = File.realdirpath(File.dirname(__FILE__))
$LOAD_PATH.unshift(APP_ROOT)

ENV["RACK_ENV"] ||= "development"

require "bundler/audit/task"
require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Bundler::Audit::Task.new

task :environment do
  require "config/environment"
end

namespace :test do
  RuboCop::RakeTask.new

  task :opts do
    ENV["TESTOPTS"] = "--verbose"
  end

  desc "Run specs"
  task :specs do |t|
    Rake::TestTask.new(t.name) do |tt|
      tt.libs << "."
      tt.test_files = Dir.glob("test/{unit,functional}/**/*.rb")
      tt.warning = false
    end
  end

  desc "Run specs with verbose output"
  task "test:verbose" => %i[opts specs]
end

desc "Run test suite"
task test: ["test:specs", "test:rubocop"]
