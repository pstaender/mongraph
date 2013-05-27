# TODO: make tests mor independent: beforeEach -> delete all relations

# source map support for coffee-script ~1.6.1
require('source-map-support').install()

expect     = require('expect.js')
mongoose   = require('mongoose')
neo4j      = require('neo4j')
mongraph   = require("../src/mongraph")
# remove all test-created nodes on every test run
cleanupNodes = true
nodesCount   = nodesCountBefore = 0 # used to check that we have deleted all created nodes during tests
Join         = require('join')

describe "Mongraph", ->

  _countNodes = (cb) -> graph.query "START n=node(*) RETURN count(n)", (err, count) ->
      cb(err, Number(count?[0]?['count(n)']) || null)

  # schemas and data objects
  Person = Location = Message = alice = bob = charles = dave = elton = frank = zoe = bar = pub = null
  # handler for connections
  mongo  = graph = null
  # regex for validating objectid
  regexID = /^[a-f0-9]{24}$/

  before (done) ->

    # Establish connections to mongodb + neo4j
    graph = new neo4j.GraphDatabase('http://localhost:7474')
    mongoose.connect("mongodb://localhost/mongraph_test")

    # initialize mongraph
    mongraph.init {
      neo4j: graph
      mongoose: mongoose
    }
    
    # Define model
    personSchema  = new mongoose.Schema(name: String)
    # for testing nesting and node storage
    messageSchema = new mongoose.Schema
      message:
        title:
          type: String
          index: true
          graph: true
        content: String
      from:
        type: String
        graph: true

    # is used for checking that we are working with the mongoose model and not with native mongodb objects
    personSchema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name

    Person   = mongoose.model "Person", personSchema
    Location = mongoose.model "Location", mongoose.Schema(name: String, lon: Number, lat: Number)
    Message  = mongoose.model "Message", messageSchema

    alice   = new Person(name: "alice")
    bob     = new Person(name: "bob")
    charles = new Person(name: "charles")
    zoe     = new Person(name: "zoe")

    bar     = new Location(name: "Bar", lon: 52.51, lat: 13.49)
    pub     = new Location(name: "Pub", lon: 40, lat: 10)

    createExampleDocuments = (cb) ->
      # create + store documents
      alice.save -> bob.save -> charles.save -> zoe.save ->
        bar.save -> pub.save ->
          cb()

    if cleanupNodes
      # remove all records
      _countNodes (err, count) ->
        nodesCountBefore = count
        Person.remove -> Location.remove -> createExampleDocuments -> 
          done()
    else
      Person.remove -> Location.remove -> createExampleDocuments -> 
        createExampleDocuments -> 
          done()

  beforeEach (done) ->
    # remove all relationships
    alice.removeRelationships '*', -> bob.removeRelationships '*', -> zoe.removeRelationships '*', ->
      bar.removeRelationships '*', -> pub.removeRelationships '*', ->
        # **knows**
        # alice -> bob -> charles -> zoe
        # bob -> zoe
        # alice <- zoe
        # **visits*
        # alice -> bar
        # alice -> pub
        alice.createRelationshipTo bob, 'knows', { since: 'years' }, ->
          alice.createRelationshipFrom zoe, 'knows', { since: 'months' }, ->
            bob.createRelationshipTo charles, 'knows', ->
              charles.createRelationshipTo zoe, 'knows', ->
                bob.createRelationshipTo zoe, 'knows', ->
                  alice.createRelationshipTo bar, 'visits', ->
                    alice.createRelationshipTo pub, 'visits', ->
                      done()
  after (done) ->
    return done() unless cleanupNodes
    # Remove all persons and locations with documents + nodes
    join = Join.create()
    for record in [ alice, bob, charles, dave, elton, zoe, bar, pub ]
      do (record) ->
        callback = join.add()
        if typeof record?.remove is 'function'
          record.remove callback
        else
          callback()
    join.when (a, b) ->
      _countNodes (err, count) ->
        if nodesCountBefore isnt count
          done(new Error("Mismatch on nodes counted before (#{nodesCountBefore}) and after (#{count}) tests"))
        else
          done()

  describe 'processtools', ->

    describe '#getObjectIDAsString()', ->
    
      it 'expect to extract the id from various kind of argument types', ->
        expect(mongraph.processtools.getObjectIDAsString(alice)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(alice._id)).to.match(regexID)
        expect(mongraph.processtools.getObjectIDAsString(String(alice._id))).to.match(regexID)

    describe '#getCollectionByCollectionName()', ->

      it 'expect to get the collection object by collection name', ->
        collection = mongraph.processtools.getCollectionByCollectionName('people')
        expect(collection.constructor).to.be.an Object

    describe '#getModelByCollectionName()', ->

      it 'expect to get the model object by collection name', ->
        model = mongraph.processtools.getModelByCollectionName('people')
        expect(model).to.be.an Object

    describe '#getModelNameByCollectionName()', ->

      it 'expect to get the model object by collection name', ->
        modelName = mongraph.processtools.getModelNameByCollectionName('people')
        expect(modelName).to.be.equal 'Person'

    describe '#sortTypeOfRelationshipAndOptionsAndCallback()', ->

      it 'expect to sort arguments', ->
        fn = mongraph.processtools.sortTypeOfRelationshipAndOptionsAndCallback
        cb = ->
        result = fn()
        expect(result).be.eql { typeOfRelationship: '*', options: {}, cb: undefined }
        result = fn(cb)
        expect(result).be.eql { typeOfRelationship: '*', options: {}, cb: cb }
        result = fn('knows', cb)
        expect(result).be.eql { typeOfRelationship: 'knows', options: {}, cb: cb }
        result = fn({debug: true}, cb)
        expect(result).be.eql { typeOfRelationship: '*', options: { debug: true }, cb: cb }
        result = fn('knows', {debug: true}, cb)
        expect(result).be.eql { typeOfRelationship: 'knows', options: { debug: true }, cb: cb }

    describe '#populateResultWithDocuments()', ->

      it 'expect to get an error and null with options as result if the data is not usable', (done) ->
        mongraph.processtools.populateResultWithDocuments null, { test: true }, (err, data, options) ->
          expect(err).to.be.an Error
          expect(data).to.be.null
          expect(options).to.be.an Object
          expect(options).to.have.keys 'test'
          done()

      it 'expect to get a node populated with the corresponding document', (done) ->
        _id = String(alice._id)
        node = graph.createNode { _collection: 'people', _id: _id }
        node.save (err, storedNode) ->
          expect(err).to.be null
          expect(storedNode).to.be.a node.constructor
          mongraph.processtools.populateResultWithDocuments storedNode, { referenceDocumentId: _id }, (err, populatedNodes, options) ->
            expect(err).to.be null
            expect(populatedNodes).to.have.length 1
            expect(populatedNodes[0].document).to.be.a 'object'
            expect(String(populatedNodes[0].document._id)).to.be.equal _id
            storedNode.delete ->
              done()
            , true

      it 'expect to get relationships populated with the corresponding documents', (done) ->
        _fromID         = String(alice._id)
        _toID           = String(bob._id)
        collectionName  = alice.constructor.collection.name
        from            = graph.createNode { _collection: 'people', _id: _fromID }
        to              = graph.createNode { _collection: 'people', _id: _toID }
        from.save (err, fromNode) -> to.save (err, toNode) ->
          fromNode.createRelationshipTo toNode, 'connected', { _from: collectionName+":"+_fromID, _to: collectionName+":"+_toID }, (err) ->
            expect(err).to.be null
            toNode.incoming 'connected', (err, foundRelationships) ->
              expect(foundRelationships).to.have.length 1
              mongraph.processtools.populateResultWithDocuments foundRelationships, (err, populatedRelationships) ->
                expect(err).to.be null
                expect(populatedRelationships).to.have.length 1
                expect(populatedRelationships[0].from).to.be.an Object
                expect(populatedRelationships[0].start).to.be.an Object
                expect(String(populatedRelationships[0].from._id)).to.be.equal _fromID
                expect(String(populatedRelationships[0].to._id)).to.be.equal _toID
                fromNode.delete ->
                  toNode.delete ->
                    done()
                  , true
                , true

      _createExamplePath = (cb) ->
        _fromID         = String(alice._id)
        _throughID      = String(bob._id)
        _toID           = String(pub._id)
        people          = alice.constructor.collection.name
        locations       = pub.constructor.collection.name
        from            = graph.createNode { _collection: 'people', _id: _fromID }
        through         = graph.createNode { _collection: 'people', _id: _throughID }
        to              = graph.createNode { _collection: 'locations', _id: _toID }
        from.save (err, fromNode) -> through.save (err, throughNode) -> to.save (err, toNode) ->
          fromNode.createRelationshipTo throughNode, 'connected', { _from: people+':'+_fromID,    _to: people+':'+_throughID }, (err) ->
            throughNode.createRelationshipTo toNode, 'connected', { _from: people+':'+_throughID, _to: locations+':'+_toID }, (err) ->
              query = """
                START  a = node(#{fromNode.id}), b = node(#{toNode.id}) 
                MATCH  p = shortestPath( a-[:connected*..3]->b )
                RETURN p;
              """
              graph.query query, (err, result) ->
                cb(err, result, [ fromNode, toNode, throughNode ])

      _removeExampleNodes = (nodes, cb) ->
        join = Join.create()
        ids = for node in nodes
          node.id
        graph.query "START n = node(#{ids.join(",")}) MATCH n-[r?]-() DELETE n, r", (err) ->
          cb(null, null)

      it 'expect to get path populated w/ corresponding documents', (done) ->
        _createExamplePath (err, result, exampleNodes) ->
          expect(err).to.be null
          expect(result).to.have.length 1
          options = { debug: true, processPart: 'p' }
          mongraph.processtools.populateResultWithDocuments result, options, (err, populatedPath, options) ->
            expect(populatedPath).to.have.length 3
            _removeExampleNodes exampleNodes, ->
              done()

      it 'expect to get path populated w/ corresponding documents with query', (done) ->
        _createExamplePath (err, result, exampleNodes) ->
          options =
            debug: true
            processPart: 'p'
            where:
              document: { name: /^[A-Z]/ }
          mongraph.processtools.populateResultWithDocuments result, options, (err, populatedPath, options) ->
            expect(populatedPath).to.have.length 1
            expect(populatedPath[0].name).match /^[A-Z]/
            _removeExampleNodes exampleNodes, ->
              done()

      it 'expect to get path populated w/ corresponding documents with distinct collection', (done) ->
        _createExamplePath (err, result, exampleNodes) ->
          options =
            debug: true
            processPart: 'p'
            collection: 'locations'
          mongraph.processtools.populateResultWithDocuments result, options, (err, populatedPath, options) ->
            expect(populatedPath).to.have.length 1
            expect(populatedPath[0].name).to.be.equal 'Pub'
            _removeExampleNodes exampleNodes, ->
              done()

  
  describe 'mongraph', ->

    describe '#init()', ->

      it 'expect that we have the all needed records in mongodb', (done) ->
        persons = []
        Person.count (err, count) ->
          expect(count).to.be.equal 4
          Location.count (err, count) ->
            expect(count).to.be.equal 2
            done()

  describe 'mongraphMongoosePlugin', ->

      describe '#schema', ->

        it 'expect to have extra attributes reserved for use with neo4j', (done) ->
          p = new Person name: 'Person'
          p.save (err, doc) ->
            expect(doc._node_id).to.be.above 0
            # checks that we can set s.th.
            doc._relationships = id: 1
            expect(doc._relationships.id).to.be.equal 1
            p.remove ->
              done()

        it 'expect that schema extensions and hooks can be optional', (done) ->
          calledPreSave = false

          join = Join.create()
          doneDisabled     = join.add()
          
          schema   = new mongoose.Schema name: String
          schema.set 'graphability', false
          Guitar   = mongoose.model "Guitar",   schema
          guitar   = new Guitar name: 'Fender'
          guitar.save (err, doc) ->
            expect(err).to.be null
            expect(doc._node_id).to.be undefined
            doc.getNode (err, node) ->
              expect(err).not.to.be null
              expect(node).to.be null
              doc.remove ->
                doneDisabled()

          doneNoDeleteHook = join.add()
          schema   = new mongoose.Schema name: String
          schema.set 'graphability', middleware: preRemove: false
          Keyboard = mongoose.model "Keyboard", schema
          keyboard = new Keyboard name: 'DX7'
          keyboard.save (err, doc) ->
            doc.getNode (err, node) ->
              # we have to delete the node manually becaud we missed out the hook
              doc.remove ->
                graph.getNodeById node.id, (err, foundNode) ->
                  expect(node).to.be.an 'object'
                  node.delete ->
                    return doneNoDeleteHook()

          # doneNoSaveHook   = join.add()
          # schema   = new mongoose.Schema name: String
          # schema.set 'graphability', middleware: preSave: false
          # # explicit overriding middleware
          # schema.pre 'save', (next) ->
          #   calledPreSave = true
          #   next()
          
          # Drumkit  = mongoose.model "Drumkit",  schema
          # drums    = new Drumkit name: 'Tama'
          # drums.save (err, doc) ->
          #   expect(err).to.be null
          #   expect(calledPreSave).to.be true
          #   expect(doc._cached_node).not.be.an 'object'
          #   drums.remove ->
          #     doneNoSaveHook()

          join.when ->
            done()


  describe 'mongoose::Document', ->

    describe '#getNode()', ->

      it 'expect not to get a corresponding node for an unstored document in graphdb', (done) ->
        elton = Person(name: "elton")
        expect(elton._node_id).not.to.be.above 0
        elton.getNode (err, found) ->
          expect(err).not.to.be null
          expect(found).to.be null
          done()

      it 'expect to find always the same corresponding node to a stored document', (done) ->
        elton = Person(name: "elton")
        elton.save (err, elton) ->
          expect(err).to.be null
          nodeID = elton._node_id
          expect(nodeID).to.be.above 0
          elton.getNode (err, node) ->
            expect(err).to.be null
            expect(node.id).to.be.equal node.id
            elton.remove() if cleanupNodes
            done()

      it 'expect to find a node by collection and _id through index on neo4j', (done) ->
        graph.getIndexedNode 'people', '_id', alice._id, (err, found) ->
          expect(found.id).to.be.equal alice._node_id
          done()

    describe '#createRelationshipTo()', ->

      it 'expect to create an outgoing relationship from this document to another document', (done) ->
        alice.createRelationshipTo bob, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship[0].start.data._id).to.be.equal (String) alice._id
          expect(relationship[0].end.data._id).to.be.equal (String) bob._id
          expect(relationship[0]._data.type).to.be.equal 'knows'
          alice.createRelationshipTo zoe, 'knows', { since: 'years' }, (err, relationship) ->
            expect(relationship[0].start.data._id).to.be.equal (String) alice._id
            expect(relationship[0].end.data._id).to.be.equal (String) zoe._id
            expect(relationship[0]._data.type).to.be.equal 'knows'
            done()

    describe '#createRelationshipFrom()', ->

      it 'expect to create an incoming relationship from another document to this document' , (done) ->
        bob.createRelationshipFrom zoe, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship[0].start.data._id).to.be.equal (String) zoe._id
          expect(relationship[0].end.data._id).to.be.equal (String) bob._id
          done()

    describe '#createRelationshipBetween()', ->

      it 'expect to create a relationship between two documents (bidirectional)', (done) ->
        alice.createRelationshipBetween bob, 'follows', ->
          bob.allRelationships 'follows', (err, bobsRelationships) ->
            value = null
            hasIncoming = false
            hasOutgoing = false
            for relationship in bobsRelationships
              hasOutgoing = relationship.from.name is 'bob' and relationship.to.name   is 'alice' unless hasOutgoing
              hasIncoming = relationship.to.name   is 'bob' and relationship.from.name is 'alice' unless hasIncoming
            expect(hasOutgoing).to.be true
            expect(hasIncoming).to.be true
            done()


    describe '#removeRelationshipsTo', ->

      it 'expect to remove outgoing relationships to a document', (done) ->
        # zoe gets to follow bob
        zoe.createRelationshipTo bob, 'follows', (err, relationship) ->
          expect(err).to.be null
          # zoe follows bob
          zoe.outgoingRelationships 'follows', (err, follows) ->
            expect(err).to.be null
            expect(follows).to.have.length 1
            expect(follows[0].to.name).to.be.equal 'bob'
            # zoe stops all 'follow' activities
            zoe.removeRelationshipsTo bob, 'follows', (err, a) ->
              expect(err).to.be null
              zoe.outgoingRelationships 'follows', (err, follows) ->
                expect(err).to.be null
                expect(follows).to.have.length 0
                done()

    describe '#removeRelationshipsFrom', ->

      it 'expects to remove incoming relationships from a document', (done) ->
        alice.incomingRelationships 'knows', (err, relationships) ->
          countBefore = relationships.length
          expect(relationships.length).to.be.equal 1
          expect(relationships[0].from.name).to.be.equal 'zoe'
          alice.removeRelationshipsFrom zoe, 'knows', (err, query, options) ->
            expect(err).to.be null
            alice.incomingRelationships 'knows',(err, relationships) ->
              expect(relationships.length).to.be.equal 0
              done()

    describe '#removeRelationshipsBetween', ->

      it 'expects to remove incoming and outgoing relationships between two documents', (done) ->
        # alice <-knows-> zoe
        alice.removeRelationships 'knows', -> zoe.removeRelationships 'knows', ->
          alice.createRelationshipTo zoe, 'knows', -> zoe.createRelationshipTo alice, 'knows', (err) ->
            alice.incomingRelationships 'knows', (err, relationships) ->
              aliceCountBefore = relationships.length
              zoe.incomingRelationships 'knows', (err, relationships) ->
                zoeCountBefore = relationships.length
                expect(relationships[0].from.name).to.be.equal 'alice'
                zoe.removeRelationshipsBetween alice, 'knows', (err) ->
                  expect(err).to.be null
                  alice.incomingRelationships 'knows', (err, aliceRelationships) ->
                    expect(aliceRelationships.length).to.be.below aliceCountBefore
                    zoe.incomingRelationships 'knows', (err, zoeRelationships) ->
                      expect(zoeRelationships.length).to.be.below zoeCountBefore
                      done()

    describe '#removeRelationships', ->

      it 'expects to remove all incoming and outgoing relationships', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships.length).to.be.above 0
          alice.removeRelationships 'knows', (err) ->
            expect(err).to.be null
            alice.allRelationships 'knows', (err, relationships) ->
              expect(relationships).to.have.length 0
              done()

      it 'expect to remove all relationship of a specific type', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships?.length).be.above 0
          alice.removeRelationships 'knows', (err, relationships) ->
            expect(relationships).to.have.length 0
            done()

    describe '#allRelationships()', ->

      it 'expect to get incoming and outgoing relationships as relationship object', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].data.since).to.be.equal 'years'
          done()

      it 'expect to get all related documents attached to relationships', (done) ->
        alice.allRelationships 'knows', (err, relationships) ->
          expect(relationships).to.be.an 'array'
          expect(relationships).to.have.length 2
          expect(relationships[0].from).to.be.an 'object'
          expect(relationships[0].to).to.be.an 'object'
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'alice', 'bob' )
          done()

      it 'expect to count all matched relationships, nodes or both', (done) ->
        alice.allRelationships { countDistinct: 'a', debug: true }, (err, res, options) ->
          count = res[0]
          expect(count).to.be.above 0
          alice.allRelationships { count: 'a', debug: true }, (err, res, options) ->
            expect(res[0]).to.be.above count
            alice.allRelationships { count: '*' }, (err, resnew, options) ->
              expect(resnew >= res[0]).to.be true
              done()

    describe '#allRelationshipsBetween()', ->

      it 'expect to get all relationships between two documents', (done) ->
        # create bidirectional relationship
        bob.createRelationshipTo alice, 'knows', { since: 'years' }, ->
          alice.allRelationshipsBetween bob, 'knows', (err, found) ->
            expect(found).to.have.length 2
            from_a = found[0].from.name
            from_b = found[1].from.name
            expect(from_a isnt from_b).to.be true
            done()

      it 'expect to get outgoing relationships between two documents', (done) ->
        # create bidirectional relationship
        bob.createRelationshipTo alice, 'knows', { since: 'years' }, ->
          alice.allRelationshipsBetween bob, 'knows', (err, found) ->
            alice.outgoingRelationshipsTo bob, 'knows', (err, found) ->
              expect(found).to.have.length 1
              bob.outgoingRelationshipsTo alice, 'knows', (err, found) ->
                expect(found).to.have.length 1
                done()

      it 'expect to get incoming relationships between two documents', (done) ->
        bob.createRelationshipTo alice, 'knows', { since: 'years' }, ->
          alice.allRelationshipsBetween bob, 'knows', (err, found) ->
            alice.incomingRelationshipsFrom bob, 'knows', (err, found) ->
              expect(found).to.have.length 1
              bob.incomingRelationshipsFrom alice, 'knows', (err, found) ->
                expect(found).to.have.length 1
                done()

    describe '#outgoingRelationships()', ->

      it 'expect to get outgoing relationships+documents from a specific collection', (done) ->
        alice.outgoingRelationships '*', { collection: 'locations' }, (err, relationships, options) ->
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'Bar', 'Pub' )
          expect(relationships).to.have.length 2
          expect(err).to.be null
          done()

      it 'expect to get incoming relationships+documents with a condition', (done) ->
        alice.outgoingRelationships '*', { where: { document: { name: /^[A-Z]/ } } }, (err, relationships) ->
          expect(relationships).to.have.length 2
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'Bar', 'Pub' )
          done()

      it 'expect to get only outgoing relationships', (done) ->
        alice.outgoingRelationships 'visits', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 2
          done()

    describe '#incomingRelationships()', ->

      it 'expect to get only incoming relationships', (done) ->
        alice.incomingRelationships 'knows', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 1
          expect(result[0].data.since).be.equal 'months'
          done()

      it 'expect to get incoming relationships+documents from a specific collection', (done) ->
        alice.incomingRelationships '*', { collection: 'people' }, (err, relationships) ->
          expect(relationships).to.have.length 1
          expect(relationships[0].from.name).to.be 'zoe'
          done()

    describe '#removeNode()', ->

      it 'expect to remove a node including all incoming and outgoing relationships', (done) ->
        frank = new Person name: 'frank'
        frank.save (err, frank) -> frank.getNode (err, node) ->
          nodeId = node.id
          expect(nodeId).to.be.above 0
          frank.createRelationshipTo zoe, 'likes', -> zoe.createRelationshipTo frank, 'likes', -> frank.allRelationships 'likes', (err, likes) ->
            expect(likes).to.have.length 2
            frank.removeNode (err, result) ->
              expect(err).to.be null
              graph.getNodeById nodeId, (err, found) ->
                expect(found).to.be undefined
                frank.allRelationships 'likes', (err, likes) ->
                  expect(likes).to.be null
                  frank.remove() if cleanupNodes
                  done()

    describe '#shortestPath()', ->

      it 'expect to get the shortest path between two documents', (done) ->
        alice.shortestPathTo zoe, 'knows', (err, path) ->
          expect(path).to.be.an 'object'
          expect(err).to.be null
          expectedPath = [ alice._id, bob._id, zoe._id ]
          for node, i in path
            expect(String(node._id)).be.equal String(expectedPath[i])
          done()
      
      it 'expect to get a mongoose document instead of a native mongodb document', (done) ->
        alice.shortestPathTo zoe, 'knows', (err, path) ->
          expect(path).to.have.length 3
          expect(path[0].fullname).to.be.equal 'alice a.'
          done()

      it 'expect to get a mongoose document with conditions', (done) ->
        alice.shortestPathTo zoe, 'knows', { where: { document: { name: /o/ } } }, (err, path) ->
          bob = path[0]
          zoe = path[1]
          expect(bob.name).to.be.equal 'bob'
          expect(zoe.name).to.be.equal 'zoe'
          expect(path).to.have.length 2
          done()

    describe '#dataForNode()', ->

      it 'expect to get null by default', (done) ->
        expect(alice.dataForNode()).to.be null
        message = new Message()
        message.message = 'how are you?'
        message.save ->
          expect(message.dataForNode()).to.be null
          message.remove ->
            done()

      it 'expect to get attributes to index', (done) ->
        message = new Message()
        index = message.dataForNode(index: true)
        expect(index).to.have.length 1
        expect(index[0]).to.be.equal 'message.title'
        done()

      it 'expect to get values for storage in node(s)'

      it 'expect to get node with indexed fields from mongoose schema'

      it 'expect to store values from document in corresponding node if defined in mongoose schema', (done) ->
        message = new Message()
        message.message.content = 'how are you?'
        message.message.title = 'hello'
        message.from = 'me'
        message.save ->
          message.getNode (err, node) ->
            expect(node).to.be.an 'object'
            expect(node.data['message.title']).to.be.equal message.message.title
            expect(node.data.from).to.be.equal message.from
            expect(node.data['message.content']).to.be undefined
            message.remove ->
              done()

    describe '#init() with specific options', ->

      it 'expect to store relationships (redundant) in document', (done) ->
        alice.applyGraphRelationships { doPersist: true }, (err, relationships) ->
          expect(err).to.be null
          expect(relationships).to.only.have.keys 'knows', 'visits'
          expect(relationships.knows).to.have.length 2
          #  remove all 'visits' relationships and check the effect on the record
          alice.removeRelationships 'visits', { debug: true }, (err, result, options) ->
            alice.applyGraphRelationships { doPersist: true }, (err, relationships) ->
              expect(err).to.be null
              expect(relationships).to.only.have.keys 'knows'
              expect(relationships.knows).to.have.length 2
              Person.findById alice._id, (err, aliceReloaded) ->
                expect(aliceReloaded._relationships).to.only.have.keys 'knows'
                expect(aliceReloaded._relationships.knows).to.have.length 2
                done()

    describe 'mongraph daily-use-test', (done) ->

      it 'expect to count relationships correctly (incoming, outgoing and both)', (done) ->
        dave  = new Person name: 'dave'
        elton = new Person name: 'elton'
        elton.save -> dave.save -> elton.allRelationships (err, eltonsRelationships) ->
          expect(err).to.be null
          expect(eltonsRelationships).to.have.length 0
          elton.createRelationshipTo dave, 'rocks', { instrument: 'piano' }, ->
            elton.outgoingRelationships 'rocks', (err, playsWith) ->
              expect(err).to.be null
              expect(playsWith).to.have.length 1
              expect(playsWith[0].data.instrument).to.be 'piano'
              elton.incomingRelationships 'rocks', (err, playsWith) ->
                expect(playsWith).to.have.length 0
                dave.createRelationshipTo elton, 'rocks', { instrument: 'guitar' }, ->
                  elton.incomingRelationships 'rocks', (err, playsWith) ->
                    expect(playsWith).to.have.length 1
                    dave.createRelationshipTo elton, 'rocks', { song: 'Everlong' }, ->
                      elton.incomingRelationships 'rocks', (err, plays) ->
                        expect(plays).to.have.length 2
                        expect(plays[0].data.instrument).to.be 'guitar'
                        expect(plays[1].data.song).to.be 'Everlong'
                        dave.allRelationships '*', (err, relations) ->
                          dave.allRelationships '*', { where: { relationship: "r.instrument! = 'guitar'" }, debug: true }, (err, relations, options) ->
                            expect(relations).to.have.length 1
                            expect(relations[0].data.instrument).to.be.equal 'guitar'
                            if cleanupNodes
                              elton.remove -> dave.remove -> done()
                            else
                              done()

  describe 'Neo4j::Node', ->

    describe '#getCollectionName()', ->

      it 'expect to get the collection name from a node', (done) ->
        # create also a new node
        emptyNode = graph.createNode()
        alice.getNode (err, node) ->
          expect(node.getCollectionName()).to.be.equal('people')
          expect(emptyNode.getCollectionName()).to.be(undefined)
          done()

    describe '#getMongoId()', ->

      it 'expect to get the id of the corresponding document from a node', (done) ->
        alice.getNode (err, node) ->
          expect(node.getMongoId()).to.be.equal (String) alice._id
          done()

    describe '#getDocument()', ->

      it 'expect to get equivalent document from a node', (done) ->
        alice.getNode (err, node) ->
          expect(node).to.be.an 'object'
          node.getDocument (err, doc) ->
            expect(doc).to.be.an 'object'
            expect(String(doc._id)).to.be.equal (String) alice._id
            done()

      
    

      
    
