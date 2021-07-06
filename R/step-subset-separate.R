#' Separate a character column into multiple columns with a regular
#' expression or numeric locations
#'
#' @description
#' This is a method for the [tidyr::separate()] generic. It is translated to
#'   [data.table::tstrsplit()] in the `j` argument of `[.data.table`.
#'
#' @param data A [lazy_dt()].
#' @param col Column name or position.
#'
#'   This argument is passed by expression and supports quasiquotation
#'   (you can unquote column names or column positions).
#' @param into Names of new variables to create as character vector.
#'   Use `NA` to omit the variable in the output.
#' @param sep Separator between columns.
#'   The default value is a regular expression that matches any sequence of non-alphanumeric values.
#' @param remove If TRUE, remove the input column from the output data frame.
#' @param convert If TRUE, will run type.convert() with as.is = TRUE on new columns.
#'   This is useful if the component columns are integer, numeric or logical.
#'
#'   NB: this will cause string "NA"s to be converted to NAs.
#' @param ... Arguments passed on to methods
#' @examples
#' library(tidyr)
#' # If you want to split by any non-alphanumeric value (the default):
#' df <- lazy_dt(data.frame(x = c(NA, "x.y", "x.z", "y.z")), "DT")
#' df %>% separate(x, c("A", "B"))
#'
#' # If you just want the second variable:
#' df %>% separate(x, c(NA, "B"))
#'
#' # Use regular expressions to separate on multiple characters:
#' df <- lazy_dt(data.frame(x = c(NA, "x?y", "x.z", "y:z")), "DT")
#' df %>% separate(x, c("A","B"), sep = "([.?:])")
#'
#' # convert = TRUE detects column classes:
#' df <- lazy_dt(data.frame(x = c("x:1", "x:2", "y:4", "z", NA)), "DT")
#' df %>% separate(x, c("key","value"), ":") %>% str
#' df %>% separate(x, c("key","value"), ":", convert = TRUE) %>% str
# exported onLoad
separate.dtplyr_step <- function(data, col, into,
                                 sep = "[^[:alnum:]]+",
                                 remove = TRUE,
                                 convert = FALSE,
                                 ...) {
  stopifnot(is.character(into))
  stopifnot(is.character(sep))

  col <- enexpr(col)

  into_length <- length(into)

  not_na_into <- !is.na(into)
  keep <- seq_along(into)[not_na_into]
  into <- into[not_na_into]

  t_str_split <- call2("tstrsplit", col, split = sep)
  if (length(keep) < into_length) {
    t_str_split$keep <- keep
  }
  if (identical(convert, TRUE)) {
    t_str_split$type.convert <- TRUE
  }

  out <- step_subset(
    data,
    vars = union(data$vars, into),
    j = call2(":=", into, t_str_split),
    needs_copy = if (data$implicit_copy) FALSE else TRUE
  )

  if (remove && !as.character(col) %in% into) {
    out <- select(out, -!!col)
  }

  out
}

# exported onLoad
separate.data.table <- function(data, col, into,
                              sep = "[^[:alnum:]]+",
                              remove = TRUE,
                              convert = FALSE,
                              ...) {
  data <- lazy_dt(data)
  tidyr::separate(
    data,
    col = {{ col }},
    into = into,
    sep = sep,
    remove = remove,
    convert = convert,
    ...
  )
}
