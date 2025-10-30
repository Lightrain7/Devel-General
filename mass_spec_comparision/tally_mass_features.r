#!/usr/bin/env Rscript

# compare_mz_rt.R
# Usage examples:
# Rscript compare_mz_rt.R --gt ground_truth.tsv --alt ft_mz_rt.csv --gt_mz mz --gt_rt rt --alt_mz mzmed --alt_rt rtmed --mz_tol 5 --rt_tol 6
# Multiple tolerances:
# Rscript compare_mz_rt.R --gt gt.csv --alt alt.csv --gt_mz mz --gt_rt rt --alt_mz mzmed --alt_rt rtmed --mz_tol 5,10 --rt_tol 6,12 --prefix myrun_

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(gridExtra)
  library(VennDiagram)
  library(scales)
})

# Helper to read CSV or Excel
read_table_auto <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("xls", "xlsx")) {
    df <- readxl::read_excel(path)
    df <- as.data.frame(df)
  } else if (ext %in% c("tsv", "txt")) {
    df <- readr::read_tsv(path, show_col_types = FALSE)
  } else if (ext %in% c("csv")) {
    df <- readr::read_csv(path, show_col_types = FALSE)
  } else {
    # fallback: try to sniff delimiter from first line
    first_line <- readLines(path, n = 1)
    if (grepl("\t", first_line)) {
      df <- readr::read_tsv(path, show_col_types = FALSE)
    } else if (grepl(",", first_line)) {
      df <- readr::read_csv(path, show_col_types = FALSE)
    } else {
      stop("Unable to determine file format for: ", path)
    }
  }
  return(df)
}


# Core comparison function
compare_features <- function(gt_df, alt_df, gt_mz_col, gt_rt_col, alt_mz_col, alt_rt_col,
                             mz_tols_ppm = c(5), rt_tols_sec = c(6),
                             out_prefix = NULL, gt_name = NULL, alt_name = NULL, out_dir = ".") {

  stopifnot(gt_mz_col %in% names(gt_df))
  stopifnot(gt_rt_col %in% names(gt_df))
  stopifnot(alt_mz_col %in% names(alt_df))
  stopifnot(alt_rt_col %in% names(alt_df))

  # prepare ground truth and alternative
  gt <- gt_df %>%
    dplyr::select(!!gt_mz_col, !!gt_rt_col) %>%
    dplyr::rename(mz = !!gt_mz_col, rt = !!gt_rt_col) %>%
    mutate(.gt_index = row_number())

  alt <- alt_df %>%
    dplyr::select(!!alt_mz_col, !!alt_rt_col) %>%
    dplyr::rename(mz = !!alt_mz_col, rt = !!alt_rt_col) %>%
    mutate(.alt_index = row_number())

  # convert RT to seconds if RT appears to be in minutes (heuristic: if max < 1000, assume minutes)
  convert_rt_seconds_if_needed <- function(x) {
    if (max(x, na.rm = TRUE) < 1000) {
      return(x * 60)
    } else {
      return(x)
    }
  }
  gt$rt_seconds <- convert_rt_seconds_if_needed(as.numeric(gt$rt))
  alt$rt_seconds <- convert_rt_seconds_if_needed(as.numeric(alt$rt))

  results_list <- list()

  for (mz_tol in mz_tols_ppm) {
    for (rt_tol in rt_tols_sec) {
      # compute absolute mz tolerance per feature: mz * (ppm / 1e6)
      # For efficiency, build outer differences
      gt_mz <- as.numeric(gt$mz)
      alt_mz <- as.numeric(alt$mz)
      gt_rt <- as.numeric(gt$rt_seconds)
      alt_rt <- as.numeric(alt$rt_seconds)

      # Use matrix differences
      # Differences
      mz_diff_abs <- abs(outer(gt_mz, alt_mz, "-"))
      mz_tol_abs <- outer(gt_mz, rep(1, length(alt_mz)), function(x, y) x * (mz_tol / 1e6))
      mz_match_mat <- mz_diff_abs <= mz_tol_abs

      rt_diff_abs <- abs(outer(gt_rt, alt_rt, "-"))
      rt_match_mat <- rt_diff_abs <= rt_tol

      match_mat <- mz_match_mat & rt_match_mat

      # tally matches per GT
      matches_per_gt <- rowSums(match_mat, na.rm = TRUE)
      matches_per_alt <- colSums(match_mat, na.rm = TRUE)

      # For Venn counts: define intersection as features with at least one match
      gt_matched_count <- sum(matches_per_gt > 0)
      alt_matched_count <- sum(matches_per_alt > 0)
      gt_total <- nrow(gt)
      alt_total <- nrow(alt)
      intersection_count <- length(unique(c(
        which(matches_per_gt > 0), # indices in GT that match
        # alternatively we could use features in ALT that match; for Venn area correctness we will compute overlap as
        # number of pairs with any mapping is ambiguous in Venn sets; choose intersection as features that participate in any match from either set trimmed to an overlap measure below
        rep(NA,0)
      )))
      # For a two-circle Venn we need: area1 = GT size, area2 = ALT size, n12 = number of unique features that belong to both sets.
      # We'll define the intersection n12 as the number of GT features that have >=1 match (GT-centric intersection).
      n12 <- gt_matched_count

      # Prepare table: per GT feature -> number of matches
      table_df <- gt %>%
        select(.gt_index, mz, rt) %>%
        mutate(matches = matches_per_gt)

      # summary stats
      most_matched_idx <- which.max(table_df$matches)
      most_matched_row <- table_df[most_matched_idx, , drop = FALSE]
      median_matches <- median(table_df$matches)

      # output filenames
      tz_mz <- ifelse(grepl("\\.", as.character(mz_tol)), gsub("\\.", "p", as.character(mz_tol)), as.character(mz_tol))
      tz_rt <- ifelse(grepl("\\.", as.character(rt_tol)), gsub("\\.", "p", as.character(rt_tol)), as.character(rt_tol))

      if (is.null(out_prefix) || out_prefix == "") {
        if (is.null(gt_name) || is.null(alt_name)) {
          prefix <- paste0("gt_alt_", tz_mz, "_", tz_rt, "_")
        } else {
          prefix <- paste0(gt_name, "_", alt_name, "_", tz_mz, "_", tz_rt, "_")
        }
      } else {
        prefix <- paste0(out_prefix, tz_mz, "_", tz_rt, "_")
      }

      table_file <- file.path(out_dir, paste0(prefix, "matches_table.csv"))
      plot_file <- file.path(out_dir, paste0(prefix, "venn_density.png"))

      # Save table
      write.csv(table_df, table_file, row.names = FALSE)

      # Create plots: Venn diagram + density of matches
      # Venn counts: gt_total, alt_total, n12
     # --- Begin replacement plotting block ---
      png(plot_file, width = 1200, height = 800, res = 150)
      grid.newpage()
     
      # layout: 4 rows: title, caption, plots, annotations
      pushViewport(viewport(layout = grid.layout(4, 2,
                                                heights = unit(c(0.08, 0.06, 0.78, 0.08), "npc"),
                                                widths  = unit(c(0.45, 0.55), "npc"))))
     
      # Title across top (row 1, cols 1-2)
      title_text <- paste0("Ground Truth vs Alternative — ", mz_tol, " ppm m/z; ", rt_tol, " s RT")
      grid.text(title_text, vp = viewport(layout.pos.row = 1, layout.pos.col = 1:2),
                gp = gpar(fontsize = 14, fontface = "bold"))
     
      # Caption (row 2, cols 1-2)
      caption <- paste0("Matching criteria: ", mz_tol, " ppm m/z; ", rt_tol,
                        " s RT. Intersection defined as ground-truth features with >=1 alternative match.")
      grid.text(caption, vp = viewport(layout.pos.row = 2, layout.pos.col = 1:2),
                gp = gpar(fontsize = 9))
     
      # Venn diagram in main left area (row 3, col 1)
      pushViewport(viewport(layout.pos.row = 3, layout.pos.col = 1))
      draw.pairwise.venn(area1 = gt_total,
                         area2 = alt_total,
                         cross.area = n12,
                         category = c(paste0("Ground truth\n(n=", gt_total, ")"),
                                      paste0("Alternative\n(n=", alt_total, ")")),
                         fill = c("#E41A1C", "#377EB8"),
                         cat.cex = 1.0,
                         cex = 1.2,
                         scaled = FALSE)
      # Add percentage labels for clarity
      grid.text(sprintf("Overlap: %d (%.3f%% of GT)", n12, 100 * n12 / gt_total),
                y = unit(0.12, "npc"), gp = gpar(fontsize = 10))
      upViewport()
     
      # Prepare histogram dataframe (table_df exists)
      table_df$matches <- as.integer(table_df$matches)
      median_matches <- median(table_df$matches)
      top_row <- table_df[which.max(table_df$matches), ]
     
      # Histogram on right (row 3, col 2)
      pushViewport(viewport(layout.pos.row = 3, layout.pos.col = 2))
      hist_plot <- ggplot(table_df, aes(x = matches)) +
        geom_histogram(binwidth = 1, fill = "gray80", color = "black", boundary = -0.5) +
        scale_x_continuous(breaks = scales::pretty_breaks()) +
        labs(x = "Number of matches per Ground truth feature", y = "Count",
             title = "Matches distribution (Ground truth)") +
        theme_minimal(base_size = 12) +
        theme(plot.title = element_text(hjust = 0.5))
     
      # add median vertical line
      hist_plot <- hist_plot +
        geom_vline(xintercept = median_matches, linetype = "dashed", color = "#D95F02", linewidth = 0.8)
     
      print(hist_plot, vp = viewport())
      upViewport()
     
      # Annotations below plots (row 4, cols 1-2)
      median_text <- paste0("Median matches: ", median_matches)
      top_text <- paste0("Top match: idx=", top_row$.gt_index, " mz=", top_row$mz, " rt=", top_row$rt, " matches=", top_row$matches)
      grid.text(median_text, vp = viewport(layout.pos.row = 4, layout.pos.col = 1),
                gp = gpar(fontsize = 10))
      grid.text(top_text, vp = viewport(layout.pos.row = 4, layout.pos.col = 2),
                gp = gpar(fontsize = 10))
     
      upViewport(0)
      dev.off()
     # --- End replacement plotting block ---


      results_list[[paste0("mz", mz_tol, "_rt", rt_tol)]] <- list(
        mz_tol = mz_tol,
        rt_tol = rt_tol,
        table = table_df,
        table_file = table_file,
        plot_file = plot_file,
        gt_total = gt_total,
        alt_total = alt_total,
        gt_matched = gt_matched_count,
        alt_matched = alt_matched_count,
        most_matched = most_matched_row,
        median_matches = median_matches
      )
    }
  }

  return(results_list)
}

# CLI parsing
option_list <- list(
  make_option(c("--gt"), type = "character", default = NULL, help = "Ground truth file path (CSV or XLSX or TSV)"),
  make_option(c("--alt"), type = "character", default = NULL, help = "Alternative file path (CSV or XLSX or TSV)"),
  make_option(c("--gt_mz"), type = "character", default = NULL, help = "Ground truth m/z column name"),
  make_option(c("--gt_rt"), type = "character", default = NULL, help = "Ground truth RT column name"),
  make_option(c("--alt_mz"), type = "character", default = NULL, help = "Alternative m/z column name"),
  make_option(c("--alt_rt"), type = "character", default = NULL, help = "Alternative RT column name"),
  make_option(c("--mz_tol"), type = "character", default = "5", help = "Comma-separated m/z tolerances in ppm, default 5"),
  make_option(c("--rt_tol"), type = "character", default = "6", help = "Comma-separated RT tolerances in seconds, default 6"),
  make_option(c("--prefix"), type = "character", default = "", help = "Output filename prefix; if empty, built from file names and tolerances"),
  make_option(c("--out_dir"), type = "character", default = ".", help = "Output directory")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Validate required args
if (is.null(opt$gt) || is.null(opt$alt) || is.null(opt$gt_mz) || is.null(opt$gt_rt) || is.null(opt$alt_mz) || is.null(opt$alt_rt)) {
  print_help(opt_parser)
  stop("Missing required arguments. Please provide --gt, --alt, --gt_mz, --gt_rt, --alt_mz, --alt_rt.")
}

# Read files
gt_df <- read_table_auto(opt$gt)
alt_df <- read_table_auto(opt$alt)

# Check columns exist
if (!(opt$gt_mz %in% names(gt_df))) stop(paste0("Ground truth mz column not found: ", opt$gt_mz))
if (!(opt$gt_rt %in% names(gt_df))) stop(paste0("Ground truth rt column not found: ", opt$gt_rt))
if (!(opt$alt_mz %in% names(alt_df))) stop(paste0("Alternative mz column not found: ", opt$alt_mz))
if (!(opt$alt_rt %in% names(alt_df))) stop(paste0("Alternative rt column not found: ", opt$alt_rt))

# Parse tolerance lists
parse_list_nums <- function(x) {
  parts <- unlist(strsplit(x, ","))
  as.numeric(parts)
}
mz_tols <- parse_list_nums(opt$mz_tol)
rt_tols <- parse_list_nums(opt$rt_tol)

gt_base <- tools::file_path_sans_ext(basename(opt$gt))
alt_base <- tools::file_path_sans_ext(basename(opt$alt))

res <- compare_features(gt_df = gt_df, alt_df = alt_df,
                        gt_mz_col = opt$gt_mz, gt_rt_col = opt$gt_rt,
                        alt_mz_col = opt$alt_mz, alt_rt_col = opt$alt_rt,
                        mz_tols_ppm = mz_tols, rt_tols_sec = rt_tols,
                        out_prefix = opt$prefix, gt_name = gt_base, alt_name = alt_base,
                        out_dir = opt$out_dir)

# Print summary to stdout
for (k in names(res)) {
  r <- res[[k]]
  cat(sprintf("Result %s: table=%s plot=%s GT_total=%d ALT_total=%d GT_matched=%d median_matches=%.1f\n",
              k, r$table_file, r$plot_file, r$gt_total, r$alt_total, r$gt_matched, r$median_matches))
}
