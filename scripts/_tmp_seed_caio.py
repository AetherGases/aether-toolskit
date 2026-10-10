"""One-off helper: verify/generate Argon2 hash and upsert Aeko Mongo user."""
from argon2 import PasswordHasher

SEED_HASH = (
    "$argon2id$v=19$m=16384,t=2,p=1$kEfZ8ZlOia6pq+HuaGut8g$"
    "$pEOpRYibo8qJvClpW7iVF87yJJj3NLR3Jw0/hz5Gjhs"
)
ph = PasswordHasher()
print("seed matches Senha123:", ph.verify(SEED_HASH, "Senha123"))
print("new hash for Senha123:", ph.hash("Senha123"))
