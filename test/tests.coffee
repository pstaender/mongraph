# TODO: make tests mor independent: beforeEach -> delete all relations

# source map support for coffee-script ~1.6.1
require('source-map-support').install()

expect     = require('expect.js')
mongoose   = require('mongoose')
neo4j      = require('neo4j')
mongraph   = require('../src/mongraph')
cleanupDBs = true # remove all test-created documents, nodes + relationship
nodesCount = nodesCountBefore = 0 # used to check that we have deleted all created nodes during tests
Join       = require('join')

describe "Mongraph", ->

  _countNodes = (cb) -> graph.query "START n=node(*) RETURN count(n)", (err, count) ->
      cb(err, Number(count?[0]?['count(n)']) || null)

  # schemas and data objects
  Person = Location = alice = bob = charles = dave = elon = zoe = bar = pub = null
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
    schema = new mongoose.Schema(name: String)

    # is used for checking that we are working with the mongoose model and not with native mongodb objects
    schema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name

    Person   = mongoose.model "Person", schema
    Location = mongoose.model "Location", mongoose.Schema(name: String, lon: Number, lat: Number)

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

    if cleanupDBs
      # remove all records
      _countNodes (err, count) ->
        nodesCountBefore = count
        Person.remove -> Location.remove -> createExampleDocuments -> 
          done()
    else
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
    return done() unless cleanupDBs
    # Remove all persons and locations with documents + nodes
    join = Join.create()
    for record in [ alice, bob, charles, dave, elon, zoe, bar, pub ]
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
        node = graph.createNode { collection: 'people', _id: _id }
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
        from            = graph.createNode { collection: 'people', _id: _fromID }
        to              = graph.createNode { collection: 'people', _id: _toID }
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
        from            = graph.createNode { collection: 'people', _id: _fromID }
        through         = graph.createNode { collection: 'people', _id: _throughID }
        to              = graph.createNode { collection: 'locations', _id: _toID }
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
          options = { debug: true }
          mongraph.processtools.populateResultWithDocuments result, options, (err, populatedPath, options) ->
            expect(populatedPath).to.have.length 3
            _removeExampleNodes exampleNodes, ->
              done()

      it 'expect to get path populated w/ corresponding documents with query', (done) ->
        _createExamplePath (err, result, exampleNodes) ->
          options =
            debug: true
            where: { name: /^[A-Z]/ }
          mongraph.processtools.populateResultWithDocuments result, options, (err, populatedPath, options) ->
            expect(populatedPath).to.have.length 1
            expect(populatedPath[0].name).match /^[A-Z]/
            _removeExampleNodes exampleNodes, ->
              done()

      it 'expect to get path populated w/ corresponding documents with distinct collection', (done) ->
        _createExamplePath (err, result, exampleNodes) ->
          options =
            debug: true
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

  describe 'mongoose::Document', ->

    describe '#getNode()', ->

      it 'expect not to get a corresponding node for an unstored document in graphdb', (done) ->
        elon = Person(name: "elon")
        expect(elon._node_id).not.to.be.above 0
        elon.getNode (err, found) ->
          expect(err).not.to.be null
          expect(found).to.be null
          done()

      it 'expect to find always the same corresponding node to a stored document', (done) ->
        elon = Person(name: "elon")
        elon.save (err, elon) ->
          expect(err).to.be null
          nodeID = elon._node_id
          expect(nodeID).to.be.above 0
          elon.getNode (err, node) ->
            expect(err).to.be null
            expect(node.id).to.be.equal node.id
            done()

    describe '#createRelationshipTo()', ->

      it 'expect to create an outgoing relationship from this document to another document', (done) ->
        alice.createRelationshipTo bob, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship.start.data._id).to.be.equal (String) alice._id
          expect(relationship.end.data._id).to.be.equal (String) bob._id
          expect(relationship._data.type).to.be.equal 'knows'
          alice.createRelationshipTo zoe, 'knows', { since: 'years' }, (err, relationship) ->
            expect(relationship.start.data._id).to.be.equal (String) alice._id
            expect(relationship.end.data._id).to.be.equal (String) zoe._id
            expect(relationship._data.type).to.be.equal 'knows'
            done()

    describe '#createRelationshipFrom()', ->

      it 'expect to create an incoming relationship from another document to this document' , (done) ->
        bob.createRelationshipFrom zoe, 'knows', { since: 'years' }, (err, relationship) ->
          expect(relationship.start.data._id).to.be.equal (String) zoe._id
          expect(relationship.end.data._id).to.be.equal (String) bob._id
          done()

    describe '#createRelationshipBetween()', ->

      it 'expect to create a relationship between two documents (bidirectional)', (done) ->
        alice.createRelationshipBetween bob, 'follows', {}, (err, relationships) ->
          expect(err).to.be null
          expect(relationships).have.length 2

          _ids = {}
          for relation in relationships
            _ids[relation.start.data._id] = true
          expect(_ids).to.only.have.keys( String(alice._id), String(bob._id) )

          done()

      it 'expect to get documents of start + end point of a relationship'#, (done) ->
        # alice.createRelationshipBetween bob, 'follows'#, (err, relationships) ->

        #   done()

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
        alice.outgoingRelationships '*', { where: { name: /^[A-Z]/ } }, (err, relationships) ->
          expect(relationships).to.have.length 2
          data = {}
          for relationship in relationships
            data[relationship.to.name] = true
          expect(data).to.only.have.keys( 'Bar', 'Pub' )
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

    describe '#outgoingRelationships()', ->

      it 'expect to get only outgoing relationshipss', (done) ->
        alice.outgoingRelationships 'visits', (err, result) ->
          expect(err).to.be(null)
          expect(result).to.have.length 2
          done()

    describe '#removeNode()', ->

      it 'expect to remove a node including all incoming and outgoing relationships', (done) ->
        dave = new Person(name: "dave")
        dave.save (err, dave) -> dave.getNode (err, node) ->
          nodeId = node.id
          expect(nodeId).to.be.above 0
          dave.createRelationshipTo zoe, 'likes', -> zoe.createRelationshipTo dave, 'likes', -> dave.allRelationships 'likes', (err, likes) ->
            expect(likes).to.have.length 2
            dave.removeNode (err, result) ->
              expect(err).to.be null
              graph.getNodeById nodeId, (err, found) ->
                expect(found).to.be undefined
                dave.allRelationships 'likes', (err, likes) ->
                  expect(likes).to.be null
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
        alice.shortestPathTo zoe, 'knows', { where: { name: /o/ } }, (err, path) ->
          bob = path[0]
          zoe = path[1]
          expect(bob.name).to.be.equal 'bob'
          expect(zoe.name).to.be.equal 'zoe'
          expect(path).to.have.length 2
          done()

    describe '#init() with specific options', ->

      it 'expect to store relationships (redundant) in document', (done) ->
        mongraph.init {
          neo4j: graph
          mongoose: mongoose
          relationships:
            storeInDocument: true
        }
        alice.save (err, record) ->
          expect(err).to.be null
          expect(record._relationships).to.be.an Object
          expect(record._relationships.visits).to.have.length 2
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

      
    
