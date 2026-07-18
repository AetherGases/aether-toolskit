// Example of init mongo code
db = db.getSiblingDB("dbAether")

db.createCollection("chats", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "chatId",
        "userId"
      ],
      properties: {
        chatId: {
          bsonType: "string"
        },
        userId: {
          bsonType: "string"
        }
      }
    }
  }
})