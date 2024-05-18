import std/[asyncdispatch, httpclient, uri, json]

type PeviitorAPI* = ref object
  apiKey: string
  updateProdURL: Uri
  updateTestURL: Uri
  updateURL*: Uri
  cleanURL*: Uri
  logoURL: Uri
  

type JobAttendance* = enum
  on_site = "on-site",
  remote = "remote"

type JobInfo* = object
  title*: string
  link*: string
  company*: string
  country* = "România"
  city*: string
  validThrough*: string
  remote*: JobAttendance

func jobObjToJson*(job: JobInfo): JsonNode =
  %* {
    "job_title": job.title,
    "job_link": $job.link,
    "company": job.company,
    "country": job.country,
    "remote": $job.remote,
    "validThrough": $job.validThrough,
    "city": $job.city
  }

proc init*(_: typedesc[PeviitorAPI], apiKey: string, prod = true): PeviitorAPI =
  if apiKey != "":
    result = new PeviitorAPI
    result.apiKey = apiKey
    result.updateProdURL =  parseUri("https://api.peviitor.ro/v4/update/")
    result.updateTestURL =  parseUri("https://api.peviitor.ro/v1/update/")
    result.logoURL =      parseUri("https://api.peviitor.ro/v1/logo/add/")
    result.cleanURL =     parseUri("https://api.peviitor.ro/v1/clean/")
    result.updateURL = if prod: result.updateProdURL
                     else: result.updateTestURL

proc clean*(api: PeviitorAPI, nume_firma: string) {.async.} =
  let http = newAsyncHttpClient(headers = newHttpHeaders({ "Content-Type": "application/x-www-form-urlencoded" }) )
  let response = await http.request(api.cleanURL, httpMethod = HttpPost, body = nume_firma)
  http.close()

proc updateJobs*(api: PeviitorAPI, jobsJson: JsonNode) {.async.} =
  var http = newAsyncHttpClient(headers = newHttpHeaders(
      { "Content-Type": "application/json",
        "apikey" : api.apiKey }))
  try:
    let response = await http.request(api.updateURL, httpMethod = HttpPost, body = $jobsJson)
    echo response.status
  except:
    echo "error trying to update josbs on " & $api.updateURL
  finally:
    http.close() 