rp = require('request-promise')
identifi = require('identifi-lib')
GUN = require('gun')
require('gun/lib/then')
require('gun/lib/load')
cheerio = require('cheerio')
Promise = require('bluebird')
fs = Promise.promisifyAll(require('fs'))
osHomedir = require('os-homedir')
datadir = process.env.IDENTIFI_DATADIR || (osHomedir() + '/.identifi')

USER_LIST_FILE = "bitcoin-otc-data/bitcoin-otc-wot.html"
RATINGDETAILS_DIR = "bitcoin-otc-data/ratingdetails"
VIEWGPG_DIR = "bitcoin-otc-data/viewgpg"
LISTING_URI = "http://bitcoin-otc.com/viewratings.php"

myIndex = null
myKey = null
msgsToAdd = []

ratingsJsonUrl = (username) ->
  "http://bitcoin-otc.com/viewratingdetail.php?nick=" +
  encodeURIComponent(username) +
  "&sign=ANY&type=RECV&outformat=json"

userJsonUrl = (username) ->
  "http://bitcoin-otc.com/viewgpg.php?nick=" +
  encodeURIComponent(username) +
  "&outformat=json"

otcUserID = (username) ->
  username + "@bitcoin-otc.com"

parseUserList = ->
  console.log "Parsing user list"
  $ = cheerio.load(fs.readFileSync(USER_LIST_FILE))
  userRows = $('table.datadisplay tr')
  users = []

  for row in userRows[2..]
    $ = cheerio.load(row)
    users.push $('td a')[0].children[0].data

  return users

downloadRatingDetails = (username) ->
  rp(ratingsJsonUrl(username))
    .catch (e) -> console.log(e)
    .then (res) ->
      fs.writeFileAsync(RATINGDETAILS_DIR + '/' + username + '.json', res)

downloadViewGPG = (username) ->
  rp(userJsonUrl(username))
    .catch (e) -> console.log(e)
    .then (res) ->
      fs.writeFileAsync(VIEWGPG_DIR + '/' + username + '.json', res)

downloadUserList = ->
  console.log "Downloading " + LISTING_URI
  rp(LISTING_URI)
    .then (res) ->
      console.log "Writing user list file"
      fs.writeFileAsync(USER_LIST_FILE, res)

download = ->
  usernames = parseUserList()
  fn = (i) ->
    return if i >= usernames.length
    username = usernames[i]
    console.log i + 1 + ' / ' + usernames.length + ' ' + username
    downloadRatingDetails(username).then ->
      downloadViewGPG(username)
    .then ->
      fn(i + 1)
  fn(0)

saveUserRatings = (filename) ->
  content = fs.readFileSync RATINGDETAILS_DIR + '/' + filename, 'utf-8'
  ratings = JSON.parse(content)
  for rating in ratings
    process.stdout.write(".")
    continue unless rating.rater_nick and rating.rated_nick
    timestamp = new Date(parseInt(parseFloat(rating.created_at) * 1000)).toISOString()
    data =
      author: [['account', otcUserID(rating.rater_nick)], ['nickname', rating.rater_nick]]
      recipient: [['account', otcUserID(rating.rated_nick)], ['nickname', rating.rated_nick]]
      rating: parseInt(rating.rating)
      comment: rating.notes
      timestamp: timestamp
      context: 'bitcoin-otc.com'
    m = await identifi.Message.createRating(data, myKey)
    msgsToAdd.push(m)
  process.stdout.write("\n")

saveUserProfile = (filename) ->
  content = fs.readFileSync VIEWGPG_DIR + '/' + filename, 'utf-8'
  ratedUser = JSON.parse(content)[0]

  if !ratedUser
    console.log filename + ': no user'
    return new Promise (resolve) -> resolve()
  ratedUserName = filename[0..-6] # remove .json

  recipient = [
    ['account', otcUserID(ratedUserName)],
    ['nickname', ratedUserName]
  ]
  recipient.push ['bitcoin', ratedUser.bitcoinaddress] if ratedUser.bitcoinaddress
  recipient.push ['gpg_fingerprint', ratedUser.fingerprint] if ratedUser.fingerprint
  recipient.push ['gpg_keyid', ratedUser.keyid] if ratedUser.keyid
  timestamp = new Date(parseInt(ratedUser.last_authed_at) * 1000)
  data =
    author: [['account', otcUserID(ratedUserName)], ['nickname', ratedUserName]],
    recipient: recipient
    timestamp: timestamp
  m = await identifi.Message.createVerification(data, myKey)
  msgsToAdd.push(m)

saveRatings = ->
  gun = new GUN(['http://localhost:8765/gun', 'https://identifi.herokuapp.com/gun'])
  myKey = await identifi.Key.getDefault()
  myIndex = await identifi.Index.create(gun.get('identifi'), {name: 'keyID', val: identifi.Key.getId(myKey)})
  m = await identifi.Message.createRating
    recipient:[['account', 'BCB@bitcoin-otc.com']],
    rating:10,
    comment:'WoT entry point'
  , myKey
  await myIndex.addMessage(m)
  p = new Promise (resolve) ->
    fs.readdir RATINGDETAILS_DIR, (err, filenames) ->
      for filename, i in filenames
        break if i >= 200
        console.log i + ' / ' + filenames.length + ' adding to identifi: ' + filename
        try
          await saveUserRatings(filename)
          await saveUserProfile(filename)
        catch e
          console.log 'crawling', filename, 'failed:', e
      resolve()
  .then ->
    console.log 'msgsToAdd.length', msgsToAdd.length
    myIndex.addMessages(msgsToAdd)
  .then (r) ->
    console.log r
    console.log 'added'

#downloadUserList()
#.then ->
#download()
saveRatings()
