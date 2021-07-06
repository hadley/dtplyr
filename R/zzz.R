# nocov start
.onLoad <- function(...) {
  register_s3_method("dplyr", "filter", "data.table")
  register_s3_method("dplyr", "intersect", "data.table")
  register_s3_method("dplyr", "setdiff", "data.table")
  register_s3_method("dplyr", "union", "data.table")
  register_s3_method("tidyr", "complete", "data.table")
  register_s3_method("tidyr", "drop_na", "data.table")
  register_s3_method("tidyr", "expand", "data.table")
  register_s3_method("tidyr", "fill", "data.table")
  register_s3_method("tidyr", "pivot_longer", "data.table")
  register_s3_method("tidyr", "pivot_wider", "data.table")
  register_s3_method("tidyr", "replace_na", "data.table")
  register_s3_method("tidyr", "nest", "data.table")
  register_s3_method("tidyr", "separate", "data.table")

  register_s3_method("dplyr", "filter", "dtplyr_step")
  register_s3_method("dplyr", "intersect", "dtplyr_step")
  register_s3_method("dplyr", "setdiff", "dtplyr_step")
  register_s3_method("dplyr", "union", "dtplyr_step")
  register_s3_method("tidyr", "complete", "dtplyr_step")
  register_s3_method("tidyr", "drop_na", "dtplyr_step")
  register_s3_method("tidyr", "expand", "dtplyr_step")
  register_s3_method("tidyr", "fill", "dtplyr_step")
  register_s3_method("tidyr", "pivot_longer", "dtplyr_step")
  register_s3_method("tidyr", "pivot_wider", "dtplyr_step")
  register_s3_method("tidyr", "replace_na", "dtplyr_step")
  register_s3_method("tidyr", "nest", "dtplyr_step")
  register_s3_method("tidyr", "separate", "dtplyr_step")
}

register_s3_method <- function(pkg, generic, class, fun = NULL) {
  stopifnot(is.character(pkg), length(pkg) == 1)
  stopifnot(is.character(generic), length(generic) == 1)
  stopifnot(is.character(class), length(class) == 1)

  if (is.null(fun)) {
    fun <- get(paste0(generic, ".", class), envir = parent.frame())
  } else {
    stopifnot(is.function(fun))
  }

  if (pkg %in% loadedNamespaces()) {
    registerS3method(generic, class, fun, envir = asNamespace(pkg))
  }

  # Always register hook in case package is later unloaded & reloaded
  setHook(
    packageEvent(pkg, "onLoad"),
    function(...) {
      registerS3method(generic, class, fun, envir = asNamespace(pkg))
    }
  )
}
# nocov end
