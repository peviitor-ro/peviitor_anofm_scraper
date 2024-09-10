import  std/[envvars, asyncdispatch, httpclient, uri, json, sequtils, strutils]
import peviitor_api/peviitorapi

proc parseWorkRegimeName(x: string): string =
  case x:
    of "Sediu": "on-site"
    else: echo "unknown work_regime_name " & x; ""

proc parseLocalityName(x: string): string =
  let parts = x.split(" > ")
  if parts[1].startsWith("MUNICIPIUL BUCURE"): return "București"
  var oras : string
  if parts.len == 3:
    oras = parts[2].toLowerAscii.split(' ').mapIt(it.capitalizeAscii()).join(" ")
  elif parts.len == 2:
    oras = parts[1].toLowerAscii.split(' ')[1..^1].mapIt(it.capitalizeAscii()).join(" ")

  oras = oras.split("-").mapIt(it.capitalizeAscii()).join("-")
  oras

proc parseAnofmJsonToPeviitorJson(job: JsonNode): JsonNode =
  %* {
    "job_title": job["occupation"].getStr(),
    "job_link": "https://mediere.anofm.ro/app/module/mediere/job/" & $job["id"].getInt(),
    "company": job["employer_name"].getStr(),
    "country": "România",
    "remote": job["work_regime_name"].getStr().parseWorkRegimeName(),
    "validThrough": job["job_expiry_date"].getStr(),
    "city": job["address_locality_name"].getStr().parseLocalityName(),
    "sursa": "anofm.ro"
  }

proc getAllOnfmJobs*(): seq[JsonNode]  =
  let jobsJson = newHttpClient().getContent("https://mediere.anofm.ro/api/entity/vw_public_job_posting").parseJson()
  for i, job in jobsJson["rows"].getElems():
    result.add job.parseAnofmJsonToPeviitorJson()

when isMainModule:
  let apiKey = if existsEnv("API_KEY"): getEnv("API_KEY")
               else: quit("API_KEY env var is not set")
  let peviitor = PeViitorAPI.init(apiKey)
  let jobs = getAllOnfmJobs() #maxReqInFlight - how may requests to keep open at any given moment
  if jobs.len != 0:
    echo "pushing " & $jobs.len & " jobs"
    waitfor peviitor.updateJobs(%jobs) #%jobs transforms seq[JsonNode] into JArray type  of those nodes
  else: echo "Error getting anofmm jobs, nothing updated"
