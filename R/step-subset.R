step_subset <- function(parent,
                        vars = parent$vars,
                        groups = parent$groups,
                        locals = parent$locals,
                        arrange = parent$arrange,
                        i = NULL,
                        j = NULL,
                        on = character(),
                        allow_cartesian = NULL,
                        needs_copy = FALSE
) {

  stopifnot(is_step(parent))
  stopifnot(is.null(i) || is_expression(i) || is_step(i))
  stopifnot(is.null(j) || is_expression(j))
  stopifnot(is.character(on))

  new_step(
    parent = parent,
    vars = vars,
    groups = groups,
    locals = locals,
    arrange = arrange,
    i = i,
    j = j,
    on = on,
    allow_cartesian = allow_cartesian,
    implicit_copy = !is.null(i) || !is.null(j),
    needs_copy = needs_copy || parent$needs_copy,
    class = "dtplyr_step_subset"
  )
}

# Grouped i needs an intermediate assignment for maximum efficiency
step_subset_i <- function(parent, i) {
  if (is_empty(i)) {
    return(parent)
  }

  if (length(parent$groups) > 0) {
    parent <- compute(parent)

    nm <- sym(parent$name)
    i <- expr((!!nm)[, .I[!!i]])              # dt[, .I[]]
    i <- add_grouping_param(i, parent, FALSE) # dt[, .I[], by = ()]
    i <- call("$", i, quote(V1))              # dt[, .I[], by = ()]$V1
  }

  step_subset(parent, i = i)
}

# When adding a subset that contains only j, it may be possible to merge
# the previous step.
step_subset_j <- function(parent,
                          vars = parent$vars,
                          groups = parent$groups,
                          arrange = parent$arrange,
                          j = NULL) {
  if (can_merge_subset(parent)) {
    i <- parent$i
    on <- parent$on
    parent <- parent$parent
  } else {
    i <- NULL
    on <- character()
  }

  step_subset(
    parent,
    vars = vars,
    groups = groups,
    arrange = arrange,
    i = i,
    j = j,
    on = on
  )
}

can_merge_subset <- function(x) {
  # Can only merge subsets
  if (!inherits(x, "dtplyr_step_subset")) {
    return(FALSE)
  }

  # Don't need to check that groups are identical because the only
  # dplyr functions that generate expression in i are
  # filter/slice/sample/arrange/join and don't affect groups

  is.null(x$j)
}

#' @export
dt_sources.dtplyr_step_subset <- function(x) {
  # TODO: need to throw error if same name refers to different tables.
  if (is_step(x$i)) {
    utils::modifyList(dt_sources(x$parent), dt_sources(x$i))
  } else {
    dt_sources(x$parent)
  }
}

#' @export
dt_call.dtplyr_step_subset <- function(x, needs_copy = x$needs_copy) {
  if (is.null(x$i) && is.null(x$j)) {
    return(dt_call(x$parent))
  }

  i <- if (is_step(x$i)) dt_call(x$i) else x$i

  parent <- dt_call(x$parent, needs_copy)

  if (is.null(i) && is.null(x$j)) {
    out <- parent
  } else if (is.null(i) && !is.null(x$j)) {
    out <- call2("[", parent, , x$j)
  } else if (!is.null(i) && is.null(x$j)) {
    out <- call2("[", parent, i)
  } else {
    out <- call2("[", parent, i, x$j)
  }

  if (!is.null(x$j)) {
    out <- add_grouping_param(out, x)
  }

  if (length(x$on) > 0) {
    out$on <- call2(".", !!!syms(x$on))
    out$allow.cartesian <- x$allow_cartesian
  }
  out
}
