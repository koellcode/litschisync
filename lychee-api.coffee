Promise = require 'bluebird'
mariastream = require 'mariastream'
tables =
    album: 'lychee_albums'
    photos: 'lychee_photos'

client = null

class HASH_NOT_EXIST_ERROR extends Error
    constructor: (message) ->
        super message

class ALBUM_CREATION_ERROR extends Error
    constructor: (message) ->
        super message

class ALBUM_NOT_EXIST_ERROR extends Error
    constructor: (message) ->
        super message

module.exports = ({host, db, user, password}) ->

    errors: ->
        HASH_NOT_EXIST_ERROR: HASH_NOT_EXIST_ERROR
        ALBUM_NOT_EXIST_ERROR: ALBUM_NOT_EXIST_ERROR

    connect: ->
        client = mariastream()
        client.on 'error', (err) ->
            console.log err

        client.connect {host, db, user, password}

    getAlbums: ->
        client.statement "SELECT title FROM #{db}.#{tables.album}"
        .readable()
        .pipe inspectpoint()
        .pipe process.stdout

    createAlbum: (title, publish = 0) -> new Promise (resolve, reject) =>
        func = "insert into #{db}.#{tables.album}"
        columns = ['title', 'sysstamp', 'public', 'password']
        statement = "#{func} (#{@_getDef columns}) VALUES (#{@_getVal columns})"
        client.statement(statement).execute
            title: title
            sysstamp: Date.now()
            public: publish
        , (err, rows, info) ->
            return reject new ALBUM_CREATION_ERROR err.message if err
            resolve id: info.insertId

    insertPhoto: (imageModel) -> new Promise (resolve, reject) =>
        delete imageModel.meta
        func = "insert into #{db}.#{tables.photos}"
        columns = Object.keys(imageModel)
        statement = "#{func} (#{@_getDef columns}) VALUES (#{@_getVal columns})"
        client.statement(statement).execute imageModel, (err, rows, info) ->
            return reject err if err
            # TODO: more semantic error handling here plz
            resolve()

    removePhoto: (checksum) -> new Promise (resolve, reject) ->
        statement = "delete from #{db}.#{tables.photos} WHERE checksum = :checksum"
        client.statement(statement).execute {checksum}, (err, rows, info) ->
            return reject err if err
            resolve()


    albumExist: (title) -> new Promise (resolve, reject) ->
        client.statement "SELECT COUNT(title) as exist, id FROM #{db}.#{tables.album} WHERE title = :title"
        .readable title: title
        .on 'data', (data) ->
            if data.exist is '0'
                reject new ALBUM_NOT_EXIST_ERROR 'album not exist in db'
            else
                resolve data

    hashExist: (sha) -> new Promise (resolve, reject) ->
        client.statement "SELECT COUNT(checksum) as exist FROM #{db}.#{tables.photos} WHERE checksum = :checksum"
        .readable checksum: sha
        .on 'data', (data) ->
            if data.exist is '0'
                reject new HASH_NOT_EXIST_ERROR 'hash not exist in db'
            else
                resolve sha
        .on 'error', (err) ->
            reject err

    _getDef: (columns) ->
        columns.join ', '

    _getVal: (columns) ->
        columns[0] = ":#{columns[0]}"
        columns.join ', :'


