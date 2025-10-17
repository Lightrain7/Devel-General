import strformat
import strutils
import os

const netcdfLibs = gorge("pkg-config --libs netcdf 2>/dev/null")
const netcdfCflags = gorge("pkg-config --cflags netcdf 2>/dev/null")

when netcdfLibs == "":
  {.error: "NetCDF library not found. Please install NetCDF (e.g., 'brew install netcdf') and ensure pkg-config is available, or set PKG_CONFIG_PATH to the correct location.".}

{.passL: netcdfLibs.strip().}
{.passC: netcdfCflags.strip().}

type
  NcType = cint
  NcId = cint

const
  NC_NOWRITE = 0
  NC_NOERR = 0

proc nc_open(path: cstring, mode: cint, ncidp: var NcId): cint {.importc, header: "<netcdf.h>".}
proc nc_close(ncid: NcId): cint {.importc, header: "<netcdf.h>".}
proc nc_inq_varid(ncid: NcId, name: cstring, varidp: var cint): cint {.importc, header: "<netcdf.h>".}
proc nc_inq_vartype(ncid: NcId, varid: cint, xtypep: var NcType): cint {.importc, header: "<netcdf.h>".}
proc nc_inq_varndims(ncid: NcId, varid: cint, ndimsp: var cint): cint {.importc, header: "<netcdf.h>".}
proc nc_inq_vardimid(ncid: NcId, varid: cint, dimidsp: ptr cint): cint {.importc, header: "<netcdf.h>".}
proc nc_inq_dimlen(ncid: NcId, dimid: cint, lenp: var csize_t): cint {.importc, header: "<netcdf.h>".}
proc nc_get_var_float(ncid: NcId, varid: cint, ip: ptr cfloat): cint {.importc, header: "<netcdf.h>".}
proc nc_get_var_double(ncid: NcId, varid: cint, ip: ptr cdouble): cint {.importc, header: "<netcdf.h>".}

type
  CdfFile = ref object
    filename: string

  # Single scan data: (retention_time, m/z, intensity)
  ScanData* = tuple[time: float64, mz: float64, intensity: float64]

  # Complete dataset with all scans
  MassSpecData* = seq[ScanData]  ## Sequence of (time, m/z, intensity) triplets

  # Alternative format for when we want all data from one scan together
  ScanBasedData* = seq[tuple[time: float64, masses: seq[float64], intensities: seq[float64]]]


proc loadCdf(filename: string): CdfFile =
  var ncid: NcId
  if nc_open(filename.cstring, NC_NOWRITE, ncid) != NC_NOERR:
    raise newException(IOError, "Could not open CDF file")
  defer: discard nc_close(ncid)
  result = CdfFile(filename: filename)
  # For simplicity, assume variables are known
  # In a full implementation, query all variables

# Data extraction using NetCDF library
proc extractData*(cdf: CdfFile, varName: string): seq[float64] =
  var ncid: NcId
  if nc_open(cdf.filename.cstring, NC_NOWRITE, ncid) != NC_NOERR:
    return @[]
  defer: discard nc_close(ncid)
  var varid: cint
  if nc_inq_varid(ncid, varName.cstring, varid) != NC_NOERR:
    return @[]
  var ndims: cint
  discard nc_inq_varndims(ncid, varid, ndims)
  var dimids = newSeq[cint](ndims)
  discard nc_inq_vardimid(ncid, varid, addr dimids[0])
  var size: csize_t = 1
  for dimid in dimids:
    var len: csize_t
    discard nc_inq_dimlen(ncid, dimid, len)
    size *= len
  var data = newSeq[float64](size)
  var ncType: NcType
  discard nc_inq_vartype(ncid, varid, ncType)
  if ncType == 5:  # NC_FLOAT
    var floatData = newSeq[cfloat](size)
    discard nc_get_var_float(ncid, varid, addr floatData[0])
    for i in 0..<size:
      data[i] = floatData[i].float64
  elif ncType == 6:  # NC_DOUBLE
    discard nc_get_var_double(ncid, varid, addr data[0])
  result = data

# Function to output delimited
proc toDelimited*(data: seq[float64], filename: string, delimiter: string = ",") =
  let f = open(filename, fmWrite)
  defer: f.close()
  for val in data:
    f.write(&"{val}{delimiter}")
  f.write("\n")

## Extract mass spectrometry data from CDF file with elution times
proc extractCdfData*(inputFile: string): MassSpecData =
  let cdf = loadCdf(inputFile)

  # Extract scan acquisition times (elution times)
  let times = cdf.extractData("scan_acquisition_time")
  if times.len == 0:
    echo "Warning: No scan_acquisition_time found, trying time_values"
    let times = cdf.extractData("time_values")
    if times.len == 0:
      echo "Error: No time data found"
      return @[]

  # Extract mass and intensity values
  let masses = cdf.extractData("mass_values")
  let intensities = cdf.extractData("intensity_values")
  if masses.len == 0 or intensities.len == 0:
    echo "Error: No mass or intensity data found"
    return @[]

  # Extract point counts for each scan
  let pointCounts = cdf.extractData("point_count")
  if pointCounts.len == 0:
    echo "Warning: No point_count found, assuming single scan"
    # If no point count, treat as single scan
    result = newSeq[ScanData](masses.len)
    for i in 0..<masses.len:
      result[i] = (times[0], masses[i], intensities[i])
    return result

  # Reconstruct scans based on point counts
  result = newSeq[ScanData]()
  var massIndex = 0
  var intensityIndex = 0

  # Check total points from point counts
  var totalPoints = 0
  for count in pointCounts:
    totalPoints += count.int

  # If point counts don't match or are all zero, use alternative structure
  if totalPoints == 0 and times.len >= 1:
    # Assume single scan structure - use first time value for all points
    result = newSeq[ScanData](masses.len)
    for i in 0..<masses.len:
      result[i] = (times[0], masses[i], intensities[i])
    return result

  if totalPoints == 0:
    echo &"Error: Cannot determine data structure. times.len={times.len}, masses.len={masses.len}"
    return @[]

  if totalPoints != masses.len:
    echo &"Warning: Point count sum ({totalPoints}) doesn't match mass/intensity array lengths ({masses.len})"

  for scanIdx in 0..<times.len:
    let pointsInScan = pointCounts[scanIdx].int
    let scanTime = times[scanIdx]

    for pointIdx in 0..<pointsInScan:
      if massIndex < masses.len and intensityIndex < intensities.len:
        result.add((scanTime, masses[massIndex], intensities[intensityIndex]))
        massIndex += 1
        intensityIndex += 1

  echo &"Extracted {result.len} data points from {times.len} scans"

## Legacy function for backward compatibility - returns (m/z, intensity) pairs only
proc extractCdfDataLegacy*(inputFile: string): seq[(float64, float64)] =
  let newData = extractCdfData(inputFile)
  result = newSeq[(float64, float64)](newData.len)
  for i in 0..<newData.len:
    result[i] = (newData[i].mz, newData[i].intensity)

## Extract data from CDF file and save to CSV/TSV file with elution times
proc extractCdfToFile*(inputFile: string, outputFile: string) =
  let data = extractCdfData(inputFile)
  if data.len == 0:
    echo "Required variables not found or empty"
    return
  let ext = outputFile.splitFile.ext.toLowerAscii()
  let isTsv = ext == ".tsv"
  let delim = if isTsv: "\t" else: ","
  let header = if isTsv: "retention_time\tmz\tintensity\n" else: "retention_time,mz,intensity\n"
  let f = open(outputFile, fmWrite)
  defer: f.close()
  f.write(header)
  for scanData in data:
    f.write(&"{scanData.time}{delim}{scanData.mz}{delim}{scanData.intensity}\n")
  echo &"Extracted {data.len} data points to {outputFile}"

# Main proc for CLI usage
# Utility function to list all variables in a CDF file
proc listCdfVariables(filename: string) =
  var ncid: NcId
  if nc_open(filename.cstring, NC_NOWRITE, ncid) != NC_NOERR:
    echo "Could not open CDF file"
    return
  defer: discard nc_close(ncid)

  echo &"Variables in {filename}:"
  # This is a simplified approach - in a full implementation you'd query all variables
  # For now, let's try common variable names used in CDF files
  let commonVars = ["scan_acquisition_time", "retention_time", "time_values",
                   "mass_values", "intensity_values", "point_count",
                   "scan_index", "scan_number", "actual_delay",
                   "a_d_sampling_rate", "scan_duration", "inter_scan_time"]

  for varName in commonVars:
    var varid: cint
    if nc_inq_varid(ncid, varName.cstring, varid) == NC_NOERR:
      echo &"  ✓ {varName}"
    else:
      echo &"  ✗ {varName}"

proc main() =
  if paramCount() == 2 and paramStr(1) == "--list-vars":
    listCdfVariables(paramStr(2))
  elif paramCount() == 2:
    extractCdfToFile(paramStr(1), paramStr(2))
  elif paramCount() == 1:
    let parts = splitFile(paramStr(1))
    let outFile = parts.dir / (parts.name & ".tsv")
    extractCdfToFile(paramStr(1), outFile)
    echo &"No output specified. Defaulting to {outFile}"
  else:
    echo "Usage: cdf_extractor [--list-vars file.cdf | input.cdf [output.(csv|tsv)]]"

when isMainModule:
  main()