dt_eval <- function(x) {
  env <- as_environment(dt_sources(x), x$env)
  add_dt_wrappers(env)

  for (var in names(x$locals)) {
    env[[var]] <- eval(x$locals[[var]], env)
  }

  quo <- new_quosure(dt_call(x), env)

  eval_tidy(quo)
}

# Make sure data.table functions are available so dtplyr still works
# even when data.table isn't attached
dt_funs <- c(
  "CJ", "copy", "dcast", "melt", "nafill",
  "fcase", "fcoalesce", "fifelse", "fintersect", "frank", "frankv", "fsetdiff", "funion",
  "setcolorder", "setnames", "tstrsplit"
)
add_dt_wrappers <- function(env) {
  env_bind(env, !!!env_get_list(ns_env("data.table"), dt_funs))
}
globalVariables(dt_funs)

# These functions attempt to simulate tidy eval as much as possible within
# data.table. The goal is to get the majority of real-world code to work,
# without aiming for 100% compliance.

capture_dots <- function(.data, ..., .j = TRUE) {
  dots <- enquos(..., .named = .j)
  dots <- lapply(dots, dt_squash, data = .data, j = .j)

  # Remove names from any list elements
  is_list <- vapply(dots, is.list, logical(1))
  names(dots)[is_list] <- ""

  # Auto-splice list results from dt_squash()
  dots[!is_list] <- lapply(dots[!is_list], list)
  unlist(dots, recursive = FALSE)
}

capture_dot <- function(.data, x, j = TRUE) {
  dt_squash(enquo(x), data = .data, j = j)
}

# squash quosures
dt_squash <- function(x, env, data, j = TRUE) {
  if (is_atomic(x) || is_null(x)) {
    x
  } else if (is_symbol(x)) {
    if (identical(x, quote(.))) {
      quote(.SD)
    } else {
      var <- as.character(x)

      if (var %in% c("T", "F")) {
        as.logical(var)
      } else if (nchar(x) > 0 && substr(var, 1, 1) == ".") {
        # data table pronouns are bound to NULL
        x
      } else if (!var %in% data$vars && env_has(env, var, inherit = TRUE)) {
        if (is_global(env)) {
          # Slightly dangerous because the variable might be modified
          # between creation and execution, but it seems like a reasonable
          # tradeoff in order to get a more natural translation.
          if (j) {
            # use .. to avoid data mask
            sym(paste0("..", var))
          } else {
            # i doesn't provide a data mask
            x
          }
        } else {
          eval(x, env)
        }
      } else {
        x
      }
    }
  } else if (is_quosure(x)) {
    dt_squash(get_expr(x), get_env(x), data, j = j)
  } else if (is_call(x, "if_any")) {
    dt_squash_if(x, env, data, j = j, reduce = "|")
  } else if (is_call(x, "if_all")) {
    dt_squash_if(x, env, data, j = j, reduce = "&")
  } else if (is_call(x, "across")) {
    dt_squash_across(x, env, data, j = j)
  } else if (is_call(x)) {
    dt_squash_call(x, env, data, j = j)
  } else {
    abort("Invalid input")
  }
}

dt_squash_call <- function(x, env, data, j = TRUE) {
  if (is_mask_pronoun(x)) {
    var <- x[[3]]
    if (is_call(x, "[[")) {
      var <- sym(eval(var, env))
    }
    if (is_symbol(x[[2]], ".data")) {
      var
    } else if (is_symbol(x[[2]], ".env")) {
      sym(paste0("..", var))
    }
  } else if (is_call(x, c("coalesce", "replace_na"))) {
    x[[1L]] <- quote(fcoalesce)
    x
  } else if (is_call(x, "case_when")) {
    # case_when(x ~ y) -> fcase(x, y)
    args <- unlist(lapply(x[-1], function(x) {
      list(
        # Get as "default" case as close as possible
        # https://github.com/Rdatatable/data.table/issues/4258
        if (isTRUE(x[[2]])) quote(rep(TRUE, .N)) else x[[2]],
        x[[3]]
      )
    }))
    args <- lapply(args, dt_squash, env = env, data = data, j = j)
    call2("fcase", !!!args)
  } else if (is_call(x, "cur_data")) {
    quote(.SD)
  } else if (is_call(x, "cur_data_all")) {
    abort("`cur_data_all()` is not available in dtplyr")
  } else if (is_call(x, "cur_group")) {
    quote(.BY)
  } else if (is_call(x, "cur_group_id")) {
    quote(.GRP)
  } else if (is_call(x, "cur_group_rows")) {
    quote(.I)
  } else if (is_call(x, "desc")) {
    x[[1]] <- sym("-")
    x[[2]] <- get_expr(x[[2]])
    x
  } else if (is_call(x, c("if_else", "ifelse"))) {
    if (is_call(x, "if_else")) {
      x <- unname(match.call(dplyr::if_else, x))
    } else {
      x <- unname(match.call(ifelse, x))
    }

    x[[1]] <- quote(fifelse)
    x[-1] <- lapply(x[-1], dt_squash, env, data, j = j)
    x
  } else if (is_call(x, "n", n = 0)) {
    quote(.N)
  } else if (is_call(x, "row_number", n = 0)) {
    quote(seq_len(.N))
  } else if (is_call(x, "row_number", n = 1)) {
    arg <- dt_squash(x[[2]], env, data, j = j)
    expr(frank(!!arg, ties.method = "first", na.last = "keep"))
  } else if (is.function(x[[1]]) || is_call(x, "function")) {
    simplify_function_call(x, env, data, j = j)
  } else {
    x[-1] <- lapply(x[-1], dt_squash, env, data, j = j)
    x
  }
}

is_mask_pronoun <- function(x) {
  is_call(x, c("$", "[["), n = 2) && is_symbol(x[[2]], c(".data", ".env"))
}

is_global <- function(env) {
  if (identical(env, globalenv())) {
    return(TRUE)
  }

  # Heuristic for inside pipe
  if (identical(env_names(env), ".") && identical(env_parent(env), globalenv())) {
    return(TRUE)
  }

  FALSE
}

simplify_function_call <- function(x, env, data, j = TRUE) {
  if (inherits(x[[1]], "inline_colwise_function")) {
    dot_var <- data$vars[[attr(x, "position")]]
    out <- replace_dot(attr(x[[1]], "formula")[[2]], sym(dot_var))
    dt_squash(out, env, data, j = j)
  } else {
    name <- fun_name(x[[1]])
    if (is.null(name)) {
      return(x)
    }

    attr(x, "position") <- NULL
    x[[1]] <- name
    dt_squash(x, env, data, j = j)
  }
}

replace_dot <- function(call, sym) {
  if (is_symbol(call, ".") || is_symbol(call, ".x")) {
    sym
  } else if (is_call(call)) {
    call[] <- lapply(call, replace_dot, sym)
    call
  } else {
    call
  }
}

has_gforce <- c(
  "min", "max", "mean", "median", "var", "sd", "sum", "prod",
  "first", "last", "head", "tail"
)
dplyr_trans <- c("n", "row_number")

fun_name <- function(fun) {
  pkg_env <- baseenv()

  for (x in has_gforce) {
    if (!env_has(pkg_env, x, inherit = TRUE))
      next

    fun_x <- env_get(pkg_env, x, inherit = TRUE)
    if (identical(fun, fun_x))
      return(sym(x))
  }

  dplyr_env <- pkg_env("dplyr")
  for (x in dplyr_trans) {
    fun_x <- env_get(dplyr_env, x, inherit = TRUE)
    if (identical(fun, fun_x))
      return(sym(x))
  }

  NULL
}
