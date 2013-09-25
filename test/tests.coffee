# source map support for coffee-script ~1.6.1
require('source-map-support').install()

neo4jURL     = 'http://localhost:7474'
mongodbURL   = 'mongodb://localhost/mongraph_test'

expect               = require('expect.js')
mongoose             = require('mongoose')
mongraph             = require("../src/mongraph") # will be overwritten by init() in before()
{Graph,Node,client}  = require('neo4jmapper')(neo4jURL)
graph                = new Graph(neo4jURL)
DocumentNode         = null # will be set in before()

Join         = require('join')
request      = require('request')

personSchema = new mongoose.Schema
  name: String
  email:
    type: String
    index: true
personSchema.virtual('fullname').get -> @name+" "+@name[0]+"." if @name
# personSchema.set('graphability', true)

# console.log(personSchema.constructor)

Person = null

describe "Mongraph", ->

  before (done) ->
    mongoose.connect(mongodbURL)
    mongraph = mongraph.init {
      mongoose: mongoose
      neo4j: neo4jURL
    }
    { DocumentNode } = mongraph
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
            DocumentNode.findOne { _id: String(alice._id) }, (err, node) ->
              expect(node.data._id).to.be String(alice._id)
              expect(node.data._collection).to.be 'people'
              done()

  it 'expect to remove a document with corresponding Node', (done) ->
    alice = new Person name: 'Alice'
    alice.save (err, alice) ->
      alice.getNode (err, node) ->
        expect(err).to.be null
        expect(node.data._id).to.be String(alice._id)
        alice.remove (err) ->
          expect(err).to.be null
          # ensure that the node doesn't exists in neo4j as well
          DocumentNode.findOne { _id: String(alice._id) }, (err, node) ->
            expect(err).to.be null
            expect(node).to.be null
            done()

  # it 'expect to query a corresponding node with a resonable url', (done) ->
  #   alice = new Person name: 'Alice'
  #   alice.save (err) ->
  #     client.get '/db/data/index/node/people/_id/'+alice._id, (err, res) ->
  #       expect(err).to.be null
  #       expect(res[0].data._id).to.be.equal alice._id.toString()
  #       done()


