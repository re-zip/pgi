# PGI

PGI is a simple and convenient interface for PostgreSQL with a few enhancements.

## PGI::DB

The `PGI::DB` handles connections to a PostgreSQL databases. It features...

* Connection Pool
* Connection auto-healing capabilities

Usage:

```ruby
DB = PGI::DB.configure do |options|
  options.pool_size = 1
  options.pool_timeout = 5
  options.pg_database = "pgi_test"
  options.pg_host = "localhost"
  options.pg_user = "pgi"
  options.pg_password = "password"
  options.logger = LOG_CATCHER
end

DB.exec_stmt("my_stmt", "SELECT 1+1")
```

## PGI::Dataset

The `PGI::Dataset` is a super light weight ActiveRecord::Relation replacement. It delivers a clean and simple querying interface:

* `#select(column1, ...)` allows you to limit the result set to only contain specified columns
* `#where(...)` - can be invoked in two ways:
  * `#where("name = $1", ['joe'])` - the classic ruby PG named paremeters
  * `#where(name: 'joe')` - as a Hash (multiple conditions will be concatenated with an ' AND ')
* `#order(:column, <:asc|:desc>)` - sort result set by column and direction, can be invoked multiple times
* `#limit(<num>)` - limits the result set to the specified number of records
* `#cursor(column: offset)` - provides a mechanism for keyset pagination. Defaults to `{ id: 0 }`
* `#first` - get the first record in a set
* `#all`- get an array of records
* `#count`- get the number of rows in a table
* `#page(:offset, :size, **where)`- get a "page" of rows of some size from some offset

```ruby
class Repository
  extend PGI::Dataset[DB, :table, cursor: { id: 0 }, scope: "age >= 21"]
end

# Select an entire row from a table
Repository
  .where(name: "joe")
  .order(:age, :asc)
  .limit(3)
  .cursor(id: 3)
# "SELECT * FROM table WHERE id > $2 AND (column = $1) ORDER BY age ASC LIMIT 3", params["joe", 3]

# Select only some columns from a table
Repository
  .select(:name)
  .where(name: "jane")
  .order(:age, :desc)
  .limit(5)
  .cursor(id: 2)
# "SELECT name FROM table WHERE id > $2 AND (column = $1) ORDER BY age DESC LIMIT 5", params["jane", 2]
```

## Documentation

Dependencies:

* https://github.com/ged/ruby-pg
* https://github.com/mperham/connection_pool

Create developer/test DB:

```
sudo su - postgres
psql -c "CREATE ROLE pgi WITH login password 'password';"
createdb --owner pgi pgi_test
psql pgi_test -c 'CREATE EXTENSION IF NOT EXISTS "pgcrypto";'
```
