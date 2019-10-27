require "crotest"
require "../src/ohm"

REDIS_HOST = ENV.fetch("REDIS_HOST", "localhost")
REDIS_PORT = ENV.fetch("REDIS_PORT", "6379")
