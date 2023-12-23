require "pg"
require "connection_pool"

module PGI
  class DB
    class JSONDecoder < PG::SimpleDecoder
      def decode(string, _tuple = nil, _field = nil)
        ::JSON.parse(string, quirks_mode: true, symbolize_names: true)
      end
    end

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
        regi = PG::BasicTypeRegistry.new.register_default_types
        regi.register_type 0, "json", PG::TextEncoder::JSON, JSONDecoder
        regi.alias_type(0, "jsonb", "json")

        PG::Connection.new(@options.pg_conn_uri).tap do |conn|
          conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: regi)
          conn.type_map_for_queries = PG::BasicTypeMapForQueries.new(conn, registry: regi)
        end
      end

      new(pool, @options.logger)
    end

    # wrapper around ConnectionPool#with with auto-healing capabilities
    #
    # @yield PG:Connection
    #
    # @See https://deveiate.org/code/pg/PG/Connection.html
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

    # Execute a prepared statement. Statements are auto-created with fallback to exec_params
    #
    # @example
    #   .exec_stmt("users_by_name", "SELECT * FROM users WHERE name = $1", ["joe"])
    #
    # @param stmt_name [String] name of statement, must be unique for the query
    # @param sql [String] SQL query
    # @param params [Array] list of params
    def exec_stmt(stmt_name, sql, params = [])
      with do |conn|
        if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS, PG::PQTRANS_INERROR].include?(conn.transaction_status)
          @logger.debug "Unable to use statements within a transaction - falling back to #exec_params"
          return conn.exec_params(sql, params)
        end

        begin
          conn.exec_prepared(stmt_name, params)
        rescue PG::InvalidSqlStatementName
          @logger.debug "Creating missing prepared statement: \"#{stmt_name}\""
          begin
            conn.prepare(stmt_name, sql) && retry
          rescue PG::SyntaxError => e
            @logger.error(e)
            raise
          end
        end
      end
    end

    # Pass the remainder of methods on to a PG::Connection
    #
    # @See https://deveiate.org/code/pg/PG/Connection.html
    def method_missing(name, ...)
      with do |conn|
        conn.__send__(name, ...)
      end
    end
  end
end
