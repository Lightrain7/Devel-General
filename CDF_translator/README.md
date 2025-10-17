# CDF Extractor

A Nim-based tool for extracting mass spectrometry data from Common Data Format (CDF) files, commonly used in mass spectrometry and metabolomics. This tool parses NetCDF-formatted CDF files and extracts m/z (mass-to-charge ratio) and intensity values into delimited formats like CSV or TSV.

## Overview 

CDF files contain raw mass spectrometry data stored in the NetCDF format. This tool provides both a standalone command-line interface for extracting data to CSV files and a Nim library for programmatic access to the data.

The tool is designed to work with ANDI (Analytical Data Interchange) CDF files, extracting the `mass_values` and `intensity_values` variables that contain the spectral data.

## Dependencies

- **Nim**: Version 2.0 or later (tested with 2.2.4)
- **NetCDF C Library**: Version 4.9.3 or compatible
- **pkg-config**: For automatic library detection

### Installing Dependencies

#### macOS (with Homebrew)
```bash
brew install nim netcdf
```

#### Linux
```bash
# Install Nim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
# Install NetCDF (Ubuntu/Debian)
sudo apt-get install libnetcdf-dev pkg-config
# Or CentOS/RHEL
sudo yum install netcdf-devel pkg-config
```

#### Windows
- Install Nim from https://nim-lang.org/download/windows.html
- Install NetCDF from https://www.unidata.ucar.edu/software/netcdf/
- Ensure pkg-config is available (via MSYS2 or similar)

## Compilation

The tool uses compile-time detection of the NetCDF library via pkg-config. If pkg-config is not available or NetCDF is not found, compilation will fail with a helpful error message.

### Building the CLI Tool

```bash
nim c cdf_extractor.nim
```

This creates an executable `cdf_extractor` that can be run from the command line.

### Building for Release

For optimized performance:

```bash
nim c -d:release cdf_extractor.nim
```

## Usage

### Command Line Interface

After compilation, run the tool with:

```bash
./cdf_extractor input.cdf [output.(csv|tsv)]
```

- `input.cdf`: Path to the input CDF file
- `output.(csv|tsv)`: Optional. If omitted, defaults to `{basename(input)}.tsv` in the same directory.

Examples:
```bash
# Default output: sample.tsv
./cdf_extractor sample.cdf

# Explicit CSV output
./cdf_extractor sample.cdf results.csv
```

The output file (CSV or TSV) will contain columns:
- `mz`: Mass-to-charge ratio values
- `intensity`: Corresponding intensity values

### Library Usage

The tool can also be imported as a Nim module in larger applications.

```nim
import cdf_extractor

# Extract data as tuples
let data: MassSpecData = extractCdfData("sample.cdf")
for (mz, intensity) in data:
  echo &"m/z: {mz}, intensity: {intensity}"

# Or save directly to file
extractCdfToFile("sample.cdf", "results.csv")
```

#### Exported Types and Procedures

- `MassSpecData`: Type alias for `seq[(float64, float64)]` - sequence of (m/z, intensity) pairs
- `extractCdfData*(inputFile: string): MassSpecData`: Extracts data programmatically
- `extractCdfToFile*(inputFile: string, outputFile: string)`: Extracts and saves to CSV/TSV file

## Error Handling

The tool includes comprehensive error handling:

- **Compilation**: Checks for NetCDF library availability
- **Runtime**: Validates CDF file format and required variables
- **Data extraction**: Handles missing variables gracefully

If required variables (`mass_values`, `intensity_values`) are not found, the tool will report this and exit cleanly.

## File Format Support

- **NetCDF Classic Format**: Fully supported
- **ANDI CDF**: Tested with sample files
- **Other NetCDF variants**: May work but not extensively tested

## Performance

The tool uses the efficient NetCDF C library for data access, providing fast extraction of large datasets (tested with 925,171+ data points).

## Contributing

This is a specialized tool for CDF data extraction. For modifications or extensions:

1. Ensure NetCDF library compatibility
2. Test with various CDF file formats
3. Maintain both CLI and library interfaces

## License

This tool is provided as-is for extracting data from CDF files. See the NetCDF library license for underlying dependencies.