# frozen_string_literal: true

# =============================
# 🧾 Solana Manual SOL Transfer (Ruby)
# =============================
# This script demonstrates:
# - Building a Solana system transfer instruction (transfer SOL)
# - Serializing the full transaction manually
# - Signing with Ed25519 using RbNaCl
# - Posting to a local Solana validator via RPC

require 'uri'
require 'json'
require 'rbnacl'
require 'base64'
require 'net/http'

require_relative 'lib/solana/utils/codecs'
Codecs = Solana::Utils::Codecs

# =============================
# 🧩 Helper: Post Request
# =============================
def send_request(body)
  uri = URI("http://localhost:8899")
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/json"
  req.body = body.to_json
  response = http.request(req)
  JSON.parse(response.body)
end

# =============================
# 🧩 Get latest blockhash
# =============================
def get_latest_blockhash
  send_request({
    id: 1,
    jsonrpc: "2.0",
    method: "getLatestBlockhash",
    params: [{ commitment: "finalized" }]
  })
  .dig("result", "value", "blockhash")
end

# =============================
# 🔐 Key Setup
# =============================

# Bob (sender)
bob_sk_bytes = JSON.load_file("bob.json")
bob_keypair = RbNaCl::Signatures::Ed25519::SigningKey.new(bob_sk_bytes[0, 32].pack("C*"))
bob_pubkey = bob_keypair.verify_key.to_bytes

# Anna (receiver)
anna_sk_bytes = JSON.load_file("anna.json")
anna_pubkey = anna_sk_bytes[32, 32].pack("C*")

# Program ID: System Program (111111...)
# 
# Many base58 decoders mis-handle the deserialization of the 
# base58 string "11111111111111111111111111111111", outputting byte sequence
# of 32 * 0x00 (32 bytes of 0s) instead of 31 * 0xFF + 0x01 (31 bytes of 0s and 1).
# If receiving a program not found error, check the system program ID.
system_program = Base58.base58_to_binary("11111111111111111111111111111111")

# =============================
# 🧩 Account Setup
# =============================

# All accounts needed for the transaction
account_keys = [
  bob_pubkey,
  anna_pubkey,
  system_program
].join

# =============================
# 📦 Build Instruction: System Transfer
# =============================

# Instruction layout:
# - program_id_index = 2
# - accounts = [
#   0 (bob),
#   1 (anna)
# ]
# - data = 4-byte instruction ID + u64 amount (LE)

instruction_data =
  [2, 0, 0, 0] + # instruction ID = 2 (System Transfer)
  Codecs.encode_le_u64(1_000_000).bytes # transferring 0.001 SOL

instruction = [
  [2].pack("C"),                                          # program ID index
  Codecs.encode_compact_u16(2),                           # num accounts
  [
    0,                                                    # bob account index
    1                                                     # anna account index
  ].pack("C*"),                                           # account indices: bob, anna
  Codecs.encode_compact_u16(instruction_data.length),     # instruction data length
  instruction_data.pack("C*")                             # instruction data
].join

# =============================
# 🧱 Build Message
# =============================

header = [
  1, # numRequiredSignatures
  0, # numReadonlySignedAccounts
  1  # numReadonlyUnsignedAccounts (system program)
].pack("C*")

# =============================
# 🧩 Get latest blockhash
# =============================
recent_blockhash = Codecs.base58_to_bytes(get_latest_blockhash).pack("C*")

message = [
  header,
  Codecs.encode_compact_u16(3),     # num account keys
  account_keys,                       # account keys
  recent_blockhash,                   # recent blockhash
  Codecs.encode_compact_u16(1),     # number of instructions
  instruction,                        # instruction
].join

# =============================
# ✍️ Sign Message
# =============================
signature = bob_keypair.sign(message)

# =============================
# 🧾 Final Transaction
# =============================
transaction = [
  Codecs.encode_compact_u16(1),  # number of signatures
  signature,
  message
].join

base64_tx = Base64.strict_encode64(transaction)
puts "Transaction: #{base64_tx}"

# =============================
# 🚀 Send via RPC to Local Validator
# =============================

result = send_request({
  id: 1,
  jsonrpc: "2.0",
  method: "sendTransaction",
  params: [base64_tx, { encoding: "base64" }]
})

puts "Response:"
puts result
