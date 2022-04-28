require "pgi/db"

module PGI
  module_function

  def configure
    opt = Struct.new(
      :pool_size, :pool_timeout, :pg_database,
      :pg_host, :pg_user, :pg_password, :logger
    ).new

    yield opt

    DB.configure do |options|
      opt.to_h.each { |k, v| options.send("#{k}=", v) }
    end
  end
end
