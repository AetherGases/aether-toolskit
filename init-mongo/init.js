// Example of init mongo code
db = db.getSiblingDB("dbAether")

db.createCollection("send_code", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "user_id",
        "email",
        "code",
        "validated",
        "created_at"
      ],
      properties: {
        user_id: {
          bsonType: "int"
        },
        email: {
          bsonType: "string"
        },
        validated: {
          bsonType: "bool"
        },
        code: {
          bsonType: "string"
        },
        created_at: {
          bsonType: "date"
        }
      }
    }
  }
})

db.send_code.createIndex(
  { "created_at": 1 },
  { expireAfterSeconds: 1800 }
)