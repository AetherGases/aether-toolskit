const dbName = "dbAether";
const dbx = db.getSiblingDB(dbName);
const names = dbx.getCollectionNames().sort();
const summary = names.map((name) => ({
  collection: name,
  count: dbx.getCollection(name).countDocuments(),
}));
printjson({ database: dbName, collections: summary });
print("--- user id_external_user=13 ---");
printjson(dbx.user.find({ id_external_user: 13 }).toArray());
