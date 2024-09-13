require "pg"
require "connection_pool"
require "pgi/connection"

module PGI
  class DB
    attr_reader :pool

    # Create instance
    #
    # @param pool [ConnectionPool]
    # @param logger [Logger]
    def initialize(pool, logger)
      @pool   = pool
      @logger = logger
    end

    def self.configure
      @options = Struct.new(
        :pool_size, :pool_timeout, :pg_conn_uri, :logger
      ).new

      yield @options

      pool = ConnectionPool.new(size: @options.pool_size, timeout: @options.pool_timeout) do
        Connection.new(conn_uri: @options.pg_conn_uri, logger: @options.logger)
      end

      new(pool, @options.logger)
    end

    # wrapper around ConnectionPool#with with auto-healing capabilities
    #
    # @yield PGI:Connection
    def transaction
      raise "Missing block" unless block_given?

      with do |conn|
        conn.transaction do |trans_conn|
          yield Connection.new(conn: trans_conn, logger: @logger)
        end
      end
    end

    # wrapper around ConnectionPool#with with auto-healing capabilities
    #
    # @yield PGI:Connection
    def with
      raise "Missing block" unless block_given?

      @pool.with do |conn| # rubocop:disable Style/ExplicitBlockArgument
        yield conn
      end
    rescue PG::ConnectionBad, PG::UnableToSend => e
      if @_retries && @_retries >= 10
        @_retries = nil
        @logger.thrown("DB connection was lost - unable to reconnect", e)
        raise
      else
        @_retries = @_retries.to_i + 1
        @logger.thrown("DB connection was lost - reconnecting(#{@_retries}/10) and retrying", e)
        @pool.reload(&:close)
        sleep 2
        retry
      end
    rescue ConnectionPool::TimeoutError => e
      @logger.thrown("Timeout in checking out DB connection from pool - retrying", e)
      retry
    end

    def exec(sql)
      with do |conn|
        conn.exec(sql)
      end
    end

    # Pass the remainder of methods on to a PGI::Connection
    #
    # @See https://deveiate.org/code/pg/PG/Connection.html
    def method_missing(name, ...)
      with do |conn|
        conn.__send__(name, ...)
      end
    end
  end
end
