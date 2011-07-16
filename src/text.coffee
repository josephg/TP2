# A TP2 implementation of text, following this spec:
# http://code.google.com/p/lightwave/source/browse/trunk/experimental/ot/README
#
# A document is made up of a string and a set of tombstones inserted throughout
# the string. For example, 'some ', (2 tombstones), 'string'.
#
# This is encoded in a document as: {s:'some string', t:[5, -2, 6]}
#
# Ops are lists of components which iterate over the whole document.
# Components are either:
#   N:         Skip N characters in the original document
#   {i:'str'}: Insert 'str' at the current position in the document
#   {t:N}:     Insert N tombstones at the current position in the document
#   {d:N}:     Delete (tombstone) N characters at the current position in the document
#
# Eg: [3, {i:'hi'}, 5, {d:8}]
#
# Snapshots are lists with characters and tombstones. Characters are stored in strings
# and adjacent tombstones are flattened into numbers.
#
# Eg, the document: 'Hello .....world' ('.' denotes tombstoned (deleted) characters)
# would be represented by a document snapshot of ['Hello ', 5, 'world']

p = -> #require('util').debug
i = -> #require('util').inspect

exports ?= {}

exports.name = 'text-tp2'

exports.tp2 = true

exports.initialVersion = () -> []

# -------- Utility methods

checkOp = (op) ->
	#	p "checkOp #{i op}"
	throw new Error('Op must be an array of components') unless Array.isArray(op)
	last = null
	for c in op
		if typeof(c) == 'object'
			if c.i != undefined
				throw new Error('Inserts must insert a string') unless typeof(c.i) == 'string' and c.i.length > 0
			else if c.d != undefined
				throw new Error('Deletes must be a +ive number') unless typeof(c.d) == 'number' and c.d > 0
			else if c.t != undefined
				throw new Error('Tombstone inserts must insert +ive tombs') unless typeof(c.t) == 'number' and c.t > 0
			else
				throw new Error('Operation component must define .i, .t or .d')
		else
			throw new Error('Op components must be objects or numbers') unless typeof(c) == 'number'
			throw new Error('Skip components must be a positive number') unless c > 0
			throw new Error('Adjacent skip components should be combined') if typeof(last) == 'number'

		last = c

# Take the next part from the specified position in a document snapshot.
# position = {index, offset}. It will be updated.
exports._takePart = takePart = (doc, position, maxlength) ->
	throw new Error 'Operation goes past the end of the document' if position.index >= doc.length

	part = doc[position.index]
	# peel off doc[0]
	result = if typeof(part) == 'string'
		part[position.offset...(position.offset + maxlength)]
	else
		Math.min(maxlength, part - position.offset)

	if (part.length || part) - position.offset > maxlength
		position.offset += maxlength
	else
		position.index++
		position.offset = 0
	
	result

# Append a part to the end of a list
exports._appendPart = appendPart = (doc, p) ->
	if doc.length == 0
		doc.push p
	else if typeof(doc[doc.length - 1]) == typeof(p)
		doc[doc.length - 1] += p
	else
		doc.push p
	return

# Apply the op to the document. The document is not modified in the process.
exports.apply = (doc, op) ->
	p "Applying #{i op} to #{i doc}"
	throw new Error('Snapshot is invalid') unless Array.isArray(doc)
	checkOp op

	newDoc = []
	position = {index:0, offset:0}

	for component in op
		if typeof(component) == 'number'
			remainder = component
			while remainder > 0
				part = takePart doc, position, remainder
				
				appendPart newDoc, part
				remainder -= part.length || part

		else if component.i != undefined
			appendPart newDoc, component.i
		else if component.t != undefined
			appendPart newDoc, component.t
		else if component.d != undefined
			remainder = component.d
			while remainder > 0
				part = takePart doc, position, remainder
				remainder -= part.length || part
			appendPart newDoc, component.d
	
	p "= #{i newDoc}"
	newDoc

# Append an op component to the end of the specified op.
# Exported for the randomOpGenerator.
exports._append = append = (op, component) ->
	#	p "append #{i op} + #{i component}"
	if component == 0 || component.i == '' || component.t == 0 || component.d == 0
		return
	else if op.length == 0
		op.push component
	else
		last = op[op.length - 1]
		if typeof(component) == 'number' && typeof(last) == 'number'
			op[op.length - 1] += component
		else if component.i != undefined && last.i?
			last.i += component.i
		else if component.t != undefined && last.t?
			last.t += component.t
		else if component.d != undefined && last.d?
			last.d += component.d
		else
			op.push component
	
	#p "-> #{i op}"
	# TODO: Comment this out once debugged.
	checkOp op

# Makes 2 functions for taking components from the start of an op, and for peeking
# at the next op that could be taken.
makeTake = (op) ->
	# The index of the next component to take
	index = 0
	# The offset into the component
	offset = 0

	# Take up to length maxlength from the op. If maxlength is not defined, there is no max.
	# If insertsIndivisible is true, inserts (& insert tombstones) won't be separated.
	#
	# Returns null when op is fully consumed.
	take = (maxlength, insertsIndivisible) ->
		p "take #{maxlength} index: #{index} off: #{offset}"
		return null if index == op.length

		e = op[index]
		if typeof((current = e)) == 'number' or (current = e.t) != undefined or (current = e.d) != undefined
			if !maxlength? or current - offset <= maxlength or (insertsIndivisible and e.t != undefined)
				# Return the rest of the current element.
				c = current - offset
				++index; offset = 0
			else
				offset += maxlength
				c = maxlength
			if e.t != undefined then {t:c} else if e.d != undefined then {d:c} else c
		else
			# Take from the inserted string
			if !maxlength? or e.i.length - offset <= maxlength or insertsIndivisible
				result = {i:e.i[offset..]}
				++index; offset = 0
			else
				result = {i:e.i[offset...offset + maxlength]}
				offset += maxlength
			result
	
	peekType = -> op[index]
	
	[take, peekType]

# Find and return the length of an op component
componentLength = (component) ->
	if typeof(component) == 'number'
		component
	else if component.i != undefined
		component.i.length
	else
		# This should work because c.d and c.t must be +ive.
		component.d or component.t

# Normalize an op, removing all empty skips and empty inserts / deletes. Concatenate
# adjacent inserts and deletes.
exports.normalize = (op) ->
	newOp = []
	append newOp, component for component in op
	newOp

# transform op1 by op2. Return transformed version of op1.
# op1 and op2 are unchanged by transform.
# idDelta should be op1.id - op2.id
exports.transform = (op, otherOp, idDelta) ->
	p "TRANSFORM op #{i op} by #{i otherOp} (delta: #{idDelta})"
	throw new Error 'idDelta not specified' unless typeof(idDelta) == 'number' and idDelta != 0

	checkOp op
	checkOp otherOp
	newOp = []

	[take, peek] = makeTake op

	for component in otherOp
		if typeof(component) == 'number' or component.d != undefined # Skip or delete
			length = component.d or component
			while length > 0
				chunk = take length, true
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				append newOp, chunk
				length -= componentLength chunk unless chunk.i or chunk.t != undefined
		else if component.i or component.t != undefined # Insert text or tombs
			if idDelta < 0
				# The server's insert should go first.
				while ((o = peek()) and (o.i or o.t != undefined))
					append newOp, take()

			# In any case, skip the inserted text.
			append newOp, component.t || component.i.length
	
	# Append extras from op1
	while (component = take())
		throw new Error "Remaining fragments in the op: #{i component}" unless component.i or component.t != undefined
		append newOp, component

	p "T = #{i newOp}"
	newOp


# Compose 2 ops into 1 op.
exports.compose = (op1, op2) ->
	p "COMPOSE #{i op1} + #{i op2}"
	checkOp op1
	checkOp op2

	result = []

	[take, _] = makeTake op1

	for component in op2
		p "component in op2 #{i component}"

		if typeof(component) == 'number' # Skip
			# Just copy from op1.
			length = component
			while length > 0
				chunk = take length
				p "take #{length} = #{i chunk}"
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				append result, chunk
				length -= componentLength chunk
				p "#{i chunk} length = #{componentLength chunk}, length -> #{length}"

		else if component.i or component.t != undefined # Insert
			clone = if component.i then {i:component.i} else {t:component.t}
			append result, clone

		else # Delete
			length = component.d
			p "delete #{length}"
			while length > 0
				chunk = take length
				p "chunk #{i chunk}"
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				chunkLength = componentLength chunk
				if chunk.i or chunk.t != undefined
					append result, {t:chunkLength}
				else
					append result, {d:chunkLength}

				length -= chunkLength
		
	# Append extras from op1
	while (component = take())
		throw new Error "Remaining fragments in op1: #{i component}" unless component.i or component.t != undefined
		append result, component

	p "= #{i result}"
	result

if window?
	window.ot ||= {}
	window.ot.types ||= {}
	window.ot.types.text = exports

