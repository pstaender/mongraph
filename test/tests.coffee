# source map support for coffee-script ~1.6.1
require('source-map-support').install()

neo4jURL     = 'http://localhost:7420'
mongodbURL   = 'mongodb://localhost/mongraph_test'

expect               = require('expect.js')
mongoose             = require('mongoose')
mongraph             = require("../lib/mongraph")
{Graph,Node,client}  = require('neo4jmapper')(neo4jURL)
graph                = new Graph(neo4jURL)

Join         = require('join')
request      = require('request')

personSchema = new mongoose.Schema(name: String)
personSchema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name
personSchema.set('graphability', true)

# console.log(personSchema.constructor)

Person = null

describe "Mongraph", ->

  before (done) ->
    mongoose.connect(mongodbURL)
    mongraph = mongraph.init {
      mongoose: mongoose
      neo4j: neo4jURL
    }
    personSchema.enableGraphability();
    Person = mongoose.model("Person", personSchema)
    done()

  describe 'init', ->

    it 'expect to have a db connection', (done) ->
      graph.about (err, status) ->
        expect(status).to.be.an 'object'
        done()

  describe 'document with corresponding node', ->

    it 'expect to create a document with a corresponding node', (done) ->
      alice = new Person name: 'Alice'
      alice.getNode (err) ->
        expect(err.message).to.be.equal "Can't get a node of an unpersisted document"
        alice.save (err) ->
          expect(err).to.be null
          alice.getNode (err, node) ->
            expect(err).to.be null
            expect(node.id).to.be.above -1
            expect(node.label).to.be.equal 'Person'
            expect(node.data._id).to.be.a 'string'
            expect(node.data._collection).to.be.equal 'people'
            # console.log node.toObject()
            done()
    #       alice.getNode (err, node) ->
    #         expect(err).to.be null
    #         id = node.id
    #         # check data
    #         expect(node.data._id).to.be.equal String(alice._id)
    #         expect(node.label).to.be.equal 'Person'
    #         expect(node.labels).to.have.length 1
    #         expect(node.labels[0]).to.be.equal 'Person'
    #         expect(node.data._collection).to.be.equal 'people'
    #         # check that we always get the same corresponding node
    #         alice.getNode (err, node) ->
    #           expect(node.id).to.be.equal id
    #           # even we have to reload the node
    #           alice._node = null
    #           alice.getNode (err, node) ->
    #             expect(node.id).to.be.equal id
    #             done()

    # it 'expect to remove a document with corresponding Node', (done) ->
    #   alice = new Person name: 'Alice'
    #   alice.save (err) ->
    #     alice.getNode (err, node) ->
    #       id = node.id
    #       expect(id).to.be.a 'number'
    #       alice.removeNode (err) ->
    #         expect(err).to.be null
    #         alice.getNode (err, node) ->
    #           expect(node.id).to.be.a 'number'
    #           expect(node.id).to.be.above id
    #           nodeID = node.id
    #           # check that it's working with the remove hook
    #           alice.remove (err) ->
    #             expect(err).to.be null
    #             Node::findById nodeID, (err, node) ->
    #               expect(err).to.be null
    #               expect(node).to.be null
    #               done()

    # it 'expect to query a corresponding node with a resonable url', (done) ->
    #   alice = new Person name: 'Alice'
    #   alice.save (err) ->
    #     client.get '/db/data/index/node/people/_id/'+alice._id, (err, res) ->
    #       expect(err).to.be null
    #       expect(res[0].data._id).to.be.equal alice._id.toString()
    #       done()


