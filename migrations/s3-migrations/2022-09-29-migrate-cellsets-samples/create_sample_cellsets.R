#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
experiment_id <- args[1]
base_path <- Sys.getenv("BIOMAGE_DATA_PATH")


# test if there is at least one argument: if not, return an error
if (length(args) != 1) {
    stop("Experiment ID must be supplied", call. = FALSE)
}

read_cellsets_json <- function(cellset_path) {
    cellsets <- jsonlite::read_json(cellset_path, simplifyVector = TRUE)
    return(cellsets)
}

get_sample_info <- function(cellsets) {

    # get place where samples are stored in cellset object
    sample_pos <- which(cellsets$cellSets$key == "sample")

    sample_ids <- cellsets$cellSets$children[[sample_pos]]$key
    sample_names <- cellsets$cellSets$children[[sample_pos]]$name
    sample_colors <- cellsets$cellSets$children[[sample_pos]]$color

    return(list(
        sample_pos = sample_pos,
        sample_ids = sample_ids,
        sample_names = sample_names,
        sample_colors = sample_colors
    ))
}


read_samples <- function(sample_ids, experiment_id, base_path) {
    scdata_list <- list()
    for (sample_id in sample_ids) {
        scdata_list[[sample_id]] <- readRDS(file.path(
            base_path,
            experiment_id,
            "raw",
            sample_id,
            "r.rds"
        ))
    }

    return(scdata_list)
}

replace_sample_cellsets <- function(scdata_list, cellsets, sample_info) {
    sample_ids <- sample_info$sample_ids

    for (i in seq_along(sample_ids)) {
        sample_id <- sample_ids[i]
        scdata <- scdata_list[[sample_id]]

        if (scdata@meta.data$samples[1] != sample_id) {
            stop("Sample ID mismatch")
        }

        cell_ids <- unname(scdata$cells_id)
        sample_pos <- sample_info$sample_pos

        cellsets$cellSets$children[[sample_pos]]$cellIds[[i]] <- cell_ids
    }

    return(cellsets)
}

migrate_experiment <- function(experiment_id, base_path) {
    experiment_path <- file.path(base_path, experiment_id)
    cellset_path <- file.path(experiment_path, "cellsets.json")

    cellsets <- read_cellsets_json(cellset_path)
    file.rename(cellset_path, paste0(cellset_path, ".old"))

    sample_info <- get_sample_info(cellsets)

    scdata_list <- read_samples(
        sample_info$sample_ids,
        experiment_id, base_path
    )

    new_cellsets <- replace_sample_cellsets(scdata_list, cellsets, sample_info)

    jsonlite::write_json(new_cellsets, cellset_path, auto_unbox = FALSE)
}

migrate_experiment(experiment_id, base_path)
