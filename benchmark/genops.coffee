type = require './src/text'
# Add the random generation functions
require './test/text'

fs = require 'fs'

file = fs.createWriteStream 'ops.json', {flags:'w'}
write = (data) -> file.write JSON.stringify(data) + '\n'

for [1..10000]
	doc = type.generateRandomDoc()
	[op1] = type.generateRandomOp doc
	[op2] = type.generateRandomOp doc

	op2_ = type.transform op2, op1, 1
	result = [op1, op2_].reduce type.apply, doc

	write {doc, op1, op2, result}

file.end()

