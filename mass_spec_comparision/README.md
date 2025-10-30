# Mass Spectrometry Feature Comparison Workflow

This R-based workflow compares two sets of mass spectrometry (MS) features to identify matches within specified tolerances for mass-to-charge ratio (m/z) and retention time (RT).

## Overview

The workflow takes two datasets of MS features and compares each feature from the "ground truth" set against all features in the "alternative" set. A match is defined when both m/z and RT fall within user-specified tolerances. The output includes:

- A table showing the number of matches for each ground truth feature
- A visualization combining a Venn diagram and histogram showing the distribution of matches

## Features

- **Flexible Input Formats**: Supports CSV, TSV, and Excel files
- **Multiple Tolerances**: Compare using different combinations of m/z and RT tolerances
- **Academic Styling**: Clean, publication-ready plots with proper layout
- **CLI and Function Interface**: Use as a command-line tool or call the function directly in R
- **Batch Processing**: Process multiple tolerance combinations in a single run

## Prerequisites

### System Requirements
- R version 4.0 or higher
- macOS, Linux, or Windows

### Required R Packages
Install the following packages:

```r
install.packages(c("optparse", "readr", "readxl", "dplyr", "tidyr", "ggplot2", "gridExtra", "VennDiagram", "scales"))
```

Or install all at once:
```bash
R -e "install.packages(c('optparse', 'readr', 'readxl', 'dplyr', 'tidyr', 'ggplot2', 'gridExtra', 'VennDiagram', 'scales'))"
```

## File Format Specifications

### Input Files
Each input file should contain columns for m/z and retention time values. Supported formats:
- CSV (comma-separated values)
- TSV (tab-separated values)
- Excel (.xls, .xlsx)

### Column Requirements
- **m/z column**: Numeric values representing mass-to-charge ratios
- **RT column**: Numeric values representing retention times
- RT values are automatically converted to seconds if they appear to be in minutes (< 1000)

### Example File Structure

Ground truth file (`ground_truth.tsv`):
```
rt	mz
6.53	117
6.65	177
6.74	217
```

Alternative file (`ft_mz_rt.csv`):
```
rn,mzmed,mzmin,mzmax,rtmed,rtmin,rtmax,npeaks,...
FT0001,50.0999984741211,50.0999984741211,50.2000007629395,308.885,...
```

## Usage

### Command Line Interface

#### Basic Usage
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz \
  --gt_rt rt \
  --alt_mz mzmed \
  --alt_rt rtmed
```

#### Multiple Tolerances
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz \
  --gt_rt rt \
  --alt_mz mzmed \
  --alt_rt rtmed \
  --mz_tol 5,10 \
  --rt_tol 6,12
```

#### Custom Output Prefix
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz \
  --gt_rt rt \
  --alt_mz mzmed \
  --alt_rt rtmed \
  --prefix my_analysis_
```

### Command Line Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--gt` | Yes | - | Ground truth file path |
| `--alt` | Yes | - | Alternative file path |
| `--gt_mz` | Yes | - | Ground truth m/z column name |
| `--gt_rt` | Yes | - | Ground truth RT column name |
| `--alt_mz` | Yes | - | Alternative m/z column name |
| `--alt_rt` | Yes | - | Alternative RT column name |
| `--mz_tol` | No | 5 | Comma-separated m/z tolerances (ppm) |
| `--rt_tol` | No | 6 | Comma-separated RT tolerances (seconds) |
| `--prefix` | No | "" | Output filename prefix |
| `--out_dir` | No | "." | Output directory |

### R Function Interface

```r
source("tally_mass_features.r")

# Load your data
gt_df <- read.table("ground_truth.tsv", header = TRUE)
alt_df <- read.csv("ft_mz_rt.csv")

# Run comparison
results <- compare_features(
  gt_df = gt_df,
  alt_df = alt_df,
  gt_mz_col = "mz",
  gt_rt_col = "rt",
  alt_mz_col = "mzmed",
  alt_rt_col = "rtmed",
  mz_tols_ppm = c(5),
  rt_tols_sec = c(6)
)
```

## Matching Algorithm

### Tolerance Calculation

For each ground truth feature, matches are found where:

1. **m/z tolerance**: `|mz_gt - mz_alt| ≤ mz_gt × (tolerance_ppm / 1,000,000)`
2. **RT tolerance**: `|rt_gt - rt_alt| ≤ tolerance_seconds`

### RT Conversion
- If RT values are < 1000, they are assumed to be in minutes and converted to seconds
- RT values ≥ 1000 are assumed to be already in seconds

### Example
For a ground truth feature with m/z = 177 and tolerance = 5 ppm:
- Tolerance window: 177 ± (177 × 5 / 1,000,000) = 177 ± 0.000885

For RT = 6.65 minutes (399 seconds) and tolerance = 6 seconds:
- Tolerance window: 399 ± 6 seconds

## Output Files

### Naming Convention
Files are named using the pattern: `{prefix}{mz_tol}_{rt_tol}_{suffix}`

If no prefix is provided, defaults to: `{gt_filename}_{alt_filename}_{mz_tol}_{rt_tol}_{suffix}`

### Table Output (CSV)
- **Columns**: `.gt_index`, `mz`, `rt`, `matches`
- **Description**: Number of matching features in alternative set for each ground truth feature

Example:
```csv
.gt_index,mz,rt,matches
1,117,6.53,0
2,177,6.65,1
3,217,6.74,0
```

### Plot Output (PNG)
- **Resolution**: 150 DPI
- **Dimensions**: 1200×800 pixels
- **Layout**:
  - Title with tolerance information
  - Venn diagram (left): Shows overlap between ground truth and alternative sets
  - Histogram (right): Distribution of matches per ground truth feature
  - Summary statistics below plots

### Venn Diagram Interpretation
- **Ground truth circle**: Total ground truth features
- **Alternative circle**: Total alternative features
- **Intersection**: Ground truth features with ≥1 match
- **Percentage**: Proportion of ground truth features with matches

## Troubleshooting

### Common Issues

1. **Column not found error**
   - Verify column names in your input files
   - Use `head -5 file.csv` to check column headers

2. **File format not recognized**
   - Ensure files have proper extensions (.csv, .tsv, .xls, .xlsx)
   - Check for proper delimiters

3. **No matches found**
   - Verify tolerance values are appropriate for your data
   - Check RT units (minutes vs seconds)

4. **R package installation issues**
   - Ensure you have write permissions for R library directory
   - Try installing packages individually if bulk install fails

### File Inspection Commands

```bash
# Check first few lines
head -5 ground_truth.tsv

# Check delimiter
file ft_mz_rt.csv

# Count lines
wc -l ground_truth.tsv
```

## Examples

### Example 1: Basic Comparison
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz --gt_rt rt \
  --alt_mz mzmed --alt_rt rtmed \
  --mz_tol 5 --rt_tol 6
```

Output files:
- `ground_truth_ft_mz_rt_5_6_matches_table.csv`
- `ground_truth_ft_mz_rt_5_6_venn_density.png`

### Example 2: Multiple Tolerances
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz --gt_rt rt \
  --alt_mz mzmed --alt_rt rtmed \
  --mz_tol 5,10,15 --rt_tol 6,12
```

Creates 6 combinations (3 m/z × 2 RT) of output files.

### Example 3: Custom Prefix
```bash
Rscript tally_mass_features.r \
  --gt ground_truth.tsv \
  --alt ft_mz_rt.csv \
  --gt_mz mz --gt_rt rt \
  --alt_mz mzmed --alt_rt rtmed \
  --mz_tol 5 --rt_tol 6 \
  --prefix experiment1_
```

Output files:
- `experiment1_5_6_matches_table.csv`
- `experiment1_5_6_venn_density.png`

## Performance Notes

- Large datasets (>10,000 features) may require significant memory
- Matrix-based comparison is efficient for most use cases
- RT conversion heuristic assumes minutes for values < 1000

## Contributing

To contribute to this workflow:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with example data
5. Submit a pull request

## License

This project is released under the MIT License. See LICENSE file for details.

## Citation

If you use this workflow in your research, please cite:

[Add appropriate citation information here]

## Support

For issues or questions:
- Check the troubleshooting section above
- Verify your R environment and package versions
- Provide example input files and command used when reporting bugs