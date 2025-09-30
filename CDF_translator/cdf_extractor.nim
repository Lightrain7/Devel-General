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

  MassSpecData* = seq[(float64, float64)]  ## Sequence of (m/z, intensity) pairs


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

## Extract mass spectrometry data from CDF file as (m/z, intensity) pairs
proc extractCdfData*(inputFile: string): MassSpecData =
  let cdf = loadCdf(inputFile)
  let masses = cdf.extractData("mass_values")
  let intensities = cdf.extractData("intensity_values")
  if masses.len == 0 or intensities.len == 0:
    return @[]
  result = newSeq[(float64, float64)](masses.len)
  for i in 0..<masses.len:
    result[i] = (masses[i], intensities[i])

## Extract data from CDF file and save to CSV file
proc extractCdfToFile*(inputFile: string, outputFile: string) =
  let data = extractCdfData(inputFile)
  if data.len == 0:
    echo "Required variables not found or empty"
    return
  let f = open(outputFile, fmWrite)
  defer: f.close()
  f.write("mz,intensity\n")
  for (mz, intensity) in data:
    f.write(&"{mz},{intensity}\n")
  echo &"Extracted {data.len} data points to {outputFile}"

# Main proc for CLI usage
proc main() =
  if paramCount() == 2:
    extractCdfToFile(paramStr(1), paramStr(2))
  else:
    echo "Usage: cdf_extractor input.cdf output.csv"

when isMainModule:
  main()