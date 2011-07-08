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
# Snapshots contain the document string and a tombstone list. The document string is simply
# a string of all the characters that have not been deleted. The tombstone list is a list of
# non-zero numbers: [4, -2, 3]. Positive numbers indiciate charaters that are not tombstoned
# (and are instead part of the document string). Negative numbers indiciate tombstones.
#
# Eg, the document: 'Hello .....world' ('.' denotes tombstoned (deleted) characters)
# would be represented by a document snapshot of {s:'Hello world', t:[6, -5, 5]}.

p = -> #require('util').debug
i = -> #require('util').inspect

exports ?= {}

exports.name = 'text-tp2'

exports.tp2 = true

exports.initialVersion = () -> {s:'', t:[]}

# -------- Utility methods

checkOp = (op) ->
	throw new Error('Op must be an array of components') unless Array.isArray(op)
	last = null
	for c in op
		if typeof(c) == 'object'
			if c.i != undefined
				throw new Error('Inserts must insert a string') unless typeof(c.i) == 'string' and c.i.length > 0
			else if c.d != undefined
				throw new Error('Deletes must be a +ive number') unless typeof(c.d) == 'number' and c.d > 0
			else if c.t != undefined
				throw new Error('Tombstone inserts must insert +ive tombs') unless typeof(c.t) == 'number' and c.i > 0
			else
				throw new Error('Operation component must define .i, .t or .d')
		else
			throw new Error('Op components must be objects or numbers') unless typeof(c) == 'number'
			throw new Error('Skip components must be a positive number') unless c > 0
			throw new Error('Adjacent skip components should be combined') if typeof(last) == 'number'

		last = c

# Makes a function for appending components to a given op.
# Exported for the randomOpGenerator.
exports._append = append = (op, component) ->
	if component == 0 || component.i == '' || component.i == 0 || component.d == ''
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
	
	# TODO: Comment this out once debugged.
	checkOp op

# Makes 2 functions for taking components from the start of an op, and for peeking
# at the next op that could be taken.
makeTake = (op) ->
	# The index of the next component to take
	idx = 0
	# The offset into the component
	offset = 0

	# Take up to length n from the front of op. If n is null, take the next
	# op component. If indivisableField == 'd', delete components won't be separated.
	# If indivisableField == 'i', insert components won't be separated.
	#
	# Returns null once op is fully consumed.
	take = (n, indivisableField) ->
		return null if idx == op.length
		#assert.notStrictEqual op.length, i, 'The op is too short to traverse the document'

		e = op[idx]
		if typeof((current = e)) == 'number' or (current = e.t) != undefined or (current = e.d) != undefined
			indivisableField = 't' if indivisableField = 'i'
			if !n? or current - offset <= n or e[indivisableField] != undefined
				# Return the rest of the current element.
				c = current - offset
				++idx; offset = 0
			else
				offset += n
				c = n
			if e.t != undefined then {t:c} else if e.d != undefined then {d:c} else c
		else
			# Take from the inserted string
			if !n? or e.i.length - offset <= n or indivisableField == 'i'
				++idx; offset = 0
				{i:e.i[offset..]}
			else
				offset += n
				{i:e.i[offset...(offset + n)]}
	
	peekType = () ->
		op[idx]
	
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

# Apply the op to the string. Returns the new string.
exports.apply = (doc, op) ->
	p "Applying #{i op} to '#{doc}'"
	{s:str, t:tombs} = doc
	throw new Error('Snapshot is invalid') unless typeof(str) == 'string' and Array.isArray(tombs)
	checkOp op

	# The position in the string
	pos = 0
	# The position in the tombstone list
	tombPos = 0
	tombOffset = 0
	# The new string, in little strings that will be .join()'ed.
	newStr = []
	newTombs = []

	appendTomb = (n) ->
		if newTombs.length == 0
			newTombs.push n
		else if (n ^ newTombs[newTombs.length - 1]) > 0 # They have the same sign
			newTombs[newTombs.length - 1] += n
		else
			newTombs.push n
		return

	consume = (n) ->
		throw new Error('Applied operation is too long') if tombPos == tombs.length
		t = Math.abs tombs[tombPos]
		if n + tombOffset >= t
			# the remainder is bigger. Consume the tomb.
			skipped = t - tombOffset
			tombOffset = 0; tombPos++
		else
			skipped = n
			tombOffset += n

		if tombs[tombPos] > 0
			pos += skipped
			skipped
		else
			-skipped

	for component in op
		if typeof(component) == 'number'
			remainder = component
			while remainder > 0
				skipped = consume remainder

				if skipped > 0
					# Consume part of the string
					throw new Error 'Operation goes past the end of the document' if pos > str.length
					newStr.push str[pos - skipped...pos]

				appendTomb skipped

		else if component.i != undefined
			newDoc.push component.i
			appendTomb component.i.length
		else if component.t != undefined
			appendTomb -component.t
		else if component.d != undefined
			remainder = component.d
			while remainder > 0
				skipped = consume remainder
				appendTomb (if skipped > 0 then skipped else -skipped)
	
	{s:newStr.join '', t:newTombs}

# transform op1 by op2. Return transformed version of op1.
# op1 and op2 are unchanged by transform.
# idDelta should be op1.id - op2.id
exports.transform = (op, otherOp, idDelta) ->
	p "TRANSFORM op #{i op} by #{i otherOp} (delta: #{idDelta}"
	throw new Error 'idDelta not specified' unless typeof(idDelta) == 'number' and idDelta != 0

	checkOp op
	checkOp otherOp
	newOp = []

	[take, peek] = makeTake op

	for component in otherOp
		if typeof(component) == 'number' or component.d != undefined # Skip or delete
			length = component.d or component
			while length > 0
				chunk = take(length, 'i')
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				append newOp, chunk
				length -= componentLength chunk unless chunk.i or chunk.t != undefined
		else if component.i or component.t != undefined # Insert text or tombs
			if idDelta < 0
				# The server's insert should go first.
				o = peek()
				append newOp, take() if o?.i or o?.t != undefined

			# In any case, skip the inserted text.
			append newOp, component.i.length
	
	# Append extras from op1
	while (component = take())
		throw new Error "Remaining fragments in the op: #{i component}" unless component.i
		append newOp, component

	newOp


# Compose 2 ops into 1 op.
exports.compose = (op1, op2) ->
	p "COMPOSE #{i op1} + #{i op2}"
	checkOp op1
	checkOp op2

	result = []

	[take, _] = makeTake op1

	for component in op2
		if typeof(component) == 'number' # Skip
			# Just copy from op1.
			length = component
			while length > 0
				chunk = take length
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				append result, chunk
				length -= componentLength chunk

		else if component.i or component.t != undefined # Insert
			append result, {i:component.i}

		else # Delete
			offset = 0
			while offset < component.d.length
				chunk = take(component.d.length - offset)
				throw new Error('The op traverses more elements than the document has') unless chunk != null

				length = componentLength chunk
				if chunk.i or chunk.t != undefined
					append result, {t:length}
				else
					append result, {d:length}

				offset += length
		
	# Append extras from op1
	throw new Error "Trailing stuff in op1" unless take() == null

	result

if window?
	window.ot ||= {}
	window.ot.types ||= {}
	window.ot.types.text = exports

