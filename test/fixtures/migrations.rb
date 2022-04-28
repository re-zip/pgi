PGI::SchemaMigrator.version(1) do |migrator|
  migrator.up do
    <<~SQL
      CREATE TABLE dataset (
        id SERIAL,
        name VARCHAR(256) NOT NULL,
        age INTEGER NOT NULL
      );
      INSERT INTO dataset (name, age) VALUES ('joe', 25)
    SQL
  end

  migrator.down do
    <<~SQL
      DROP TABLE IF EXISTS dataset;
    SQL
  end
end
