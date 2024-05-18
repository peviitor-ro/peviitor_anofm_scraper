import  std/[envvars, asyncdispatch, httpclient, uri, json, sequtils, strutils]
import curly
import peviitor_api/peviitorapi

proc anofmGetJobsIds*(): Future[seq[int]] {.async.} = 
  let http = newAsyncHttpClient()
  let url = parseUri("https://www.anofm.ro/dmxConnect/api/oferte_bos/totaluriLmvInitial.php?judet=ANOFM&localitatea=")
  let jobIdsJson = parseJson await http.getContent(url)
  return jobIdsJson["queryTotaluri"].mapIt(it["POSTED_JOBS_ID"].getInt())

proc anofmGetJobInfo*(id: int): Future[JsonNode] {.async.} =
  let http = newAsyncHttpClient()
  let url = parseUri("https://www.anofm.ro/dmxConnect/api/oferte_bos/detalii_lmv_test.php?id_lmv=" & $id)
  var jobInfo: JsonNode
  try:
    jobInfo = parseJson await http.getContent(url)
  except:
    echo "error on job " & $id
  echo "Got job " & $id
  jobInfo   

#[
func parseAnofmJsonToJobInfoObj(job: JsonNode): JobInfo =
  JobInfo(
    title: job["detalii_lmv"][0]["ocupatie"].getStr(),
    link: "https://www.anofm.ro/lmvw.html?agentie=ANOFM&categ=3&subcateg=1&id_lmv=" & $job["detalii_lmv"][0]["POSTED_JOBS_ID"].getInt(),
    company: job["detalii_lmv"][0]["AGENT"].getStr(),
    city: job["detalii_lmv"][0]["ADRESA_LOCALITATEA"].getStr(),
    country: "Romania",
    validThrough: job["detalii_lmv"][0]["EXPIRATION_DATE"].getStr(),
    remote: JobAttendance.on_site
    )]#

func parseAnofmJsonToPeviitorJson(job: JsonNode): JsonNode =
  %* {
    "job_title": job["detalii_lmv"][0]["ocupatie"].getStr(),
    "job_link": "https://www.anofm.ro/lmvw.html?agentie=ANOFM&categ=3&subcateg=1&id_lmv=" & $job["detalii_lmv"][0]["POSTED_JOBS_ID"].getInt(),
    "company": job["detalii_lmv"][0]["AGENT"].getStr(),
    "country": "Romania",
    "remote": "on-site",
    "validThrough": job["detalii_lmv"][0]["EXPIRATION_DATE"].getStr(),
    "city": job["detalii_lmv"][0]["ADRESA_LOCALITATEA"].getStr()
  }

proc getAllOnfmJobs*(maxReqInFlight: int = 64): Future[seq[JsonNode]] {.async.} =
  let curl = newCurly(maxInFlight = maxReqInFlight)
  var batch: RequestBatch
  var jsons: seq[JsonNode]

  let jobIds = waitFor anofmGetJobsIds()
  echo "got " & $jobIds.len & " job indexes from anofm"

  for id in jobIds:
    batch.get("https://www.anofm.ro/dmxConnect/api/oferte_bos/detalii_lmv_test.php?id_lmv=" & $id)

  var errorsN = 0
  for (response, error) in curl.makeRequests(batch): # blocks until all are complete
    if error == "":
      jsons.add(response.body.parseJson().parseAnofmJsonToPeviitorJson())
    else:
      echo error
      var retries = 0
      let http = newAsyncHttpClient()
      var success = false
      while retries < 10:
        try:
          let resp = await http.getContent(response.url)
          jsons.add(resp.parseJson().parseAnofmJsonToPeviitorJson())
          success = true
        except:
          retries += 1
          await sleepAsync 1000
      if not success: inc errorsN
      http.close()
  echo "we got " & $errorsN & " jobs with errors on anofm"
  return jsons

when isMainModule:
  let apiKey = if existsEnv("API_KEY"): getEnv("API_KEY")
               else: quit("API_KEY env var is not set")

  let peviitor = PeViitorAPI.init(apiKey)
  let jobs = waitFor getAllOnfmJobs(maxReqInFlight = 16) #maxReqInFlight - how may requests to keep open at any given moment
  if jobs.len != 0:
     waitFor peviitor.updateJobs(%jobs) #%jobs transforms seq[JsonNode] into JArray type  of those nodes
  else: echo "Error getting anofmm jobs, nothing updated"