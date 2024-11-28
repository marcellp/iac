#!/usr/bin/env Rscript

read_rds_list <- function(in_file_paths) {
    rds_list <- c()

    for (i in seq_along(in_file_paths)) {
        rds_list[[i]] <- readRDS(in_file_paths[[i]])
    }

    return(rds_list)
}

save_rds_list <- function(rds_list, in_file_paths) {
    out_file_paths <- gsub("/in/", "/out/", in_file_paths)

    for (i in seq_along(rds_list)) {
        folder_path <- dirname(out_file_paths[[i]])

        # Create the folder if it doesn't exist
        if (!file.exists(folder_path)) {
            dir.create(folder_path, recursive = TRUE)
        }

        print(paste0("--- Saving to ", out_file_paths[[i]]))

        saveRDS(rds_list[[i]], out_file_paths[[i]])
    }
}

fix_source <- function(experiment_id, sample_ids, rds_list) {
    for (i in seq_along(rds_list)) {
        rds_list[[i]]@meta.data$samples <- sample_ids[[i]]
        rds_list[[i]]@misc$experimentId <- experiment_id
    }

    return(rds_list)
}

migrate <- function(experiment_id, base_path) {
    in_file_paths <- list.files(
        file.path(base_path, experiment_id, "raw"),
        full.names = TRUE
    )

    in_file_paths <- paste0(in_file_paths, "/r.rds")

    sample_ids <- list.files(
        file.path(base_path, experiment_id, "raw"),
        full.names = FALSE
    )

    print("--- Reading list of rds files")

    rds_list <- read_rds_list(in_file_paths)

    print("--- Fixing files")
    rds_list <- fix_source(experiment_id, sample_ids, rds_list)

    print("--- Saving fixed files")
    save_rds_list(rds_list, in_file_paths)
}

args <- commandArgs(trailingOnly = TRUE)
experiment_id <- args[1]
base_path <- Sys.getenv("BIOMAGE_DATA_PATH")


# test if there is at least one argument: if not, return an error
if (length(args) != 1) {
    stop("Experiment ID must be supplied", call. = FALSE)
}

migrate(experiment_id, base_path)