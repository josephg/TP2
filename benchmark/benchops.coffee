type = require './src/text'
fs = require 'fs'
assert = require 'assert'

check = (ops, check) ->
	for {doc, op1, op2, result} in ops
		op1_ = type.transform op1, op2, -1
		op2_ = type.transform op2, op1, 1

		op12 = type.compose op1, op2_
		op21 = type.compose op2, op1_

		doc12 = type.apply doc, op12
		doc21 = type.apply doc, op21

		if check
			assert.deepEqual doc12, doc21
			assert.deepEqual doc12, result

	return


ops = for line in fs.readFileSync('ops.json', 'utf8').split('\n') when line != ''
	JSON.parse line

console.log "Read #{ops.length} ops"
console.time 'check'
check ops, false for [1..100]
console.timeEnd 'check'
