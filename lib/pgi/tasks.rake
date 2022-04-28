namespace :db do
  def current_version
    PGI::SchemaMigrator.current_version
  end

  task :migration_env do
    require "pgi/schema_migrator"
  end

  desc "Prints current schema version"
  task version: [:migration_env] do
    puts "Schema Version: #{current_version}"
  end

  desc "Perform migration up to latest migration available"
  task migrate: [:migration_env] do
    PGI::SchemaMigrator.migrate!
    Rake::Task["db:version"].execute
  end

  # TODO: Don't rollback to version = 0 by default
  desc "Perform rollback to specified target or full rollback as default"
  task :rollback, [:target] => [:migration_env] do |_, args|
    args.with_defaults(target: 0)

    if args.target.to_i < current_version
      puts "WARNING: You are about to rollback migration from version #{current_version} to #{args.target}"
      5.downto(1) do |i|
        print "\rI'm giving you #{i} seconds to regret and abort", ".. "
        sleep 1
      end
      puts
    end

    PGI::SchemaMigrator.migrate! args[:target].to_i
    Rake::Task["db:version"].execute
  end

  desc "Perform migration reset (full rollback and migration)"
  task reset: [:migration_env] do
    unless %w[development test staging ci].include?(ENV["RACK_ENV"])
      warn "Reset not allowed for environment #{ENV["RACK_ENV"].inspect}"
      exit 1
    end

    PGI::SchemaMigrator.migrate! 0
    PGI::SchemaMigrator.migrate!
    Rake::Task["db:seed"].execute
    Rake::Task["db:version"].execute
  end

  desc "Seed database"
  task seed: [:migration_env] do
    puts "Seeding database with test data..."
    PGI::SchemaMigrator.config.seed_files.each { |file| require file }
  end
end
