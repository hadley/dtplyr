test_that("expand completes all values", {
  tbl <- tibble(x = 1:2, y = 1:2)
  dt <- lazy_dt(tbl, "DT")
  step <- expand(dt, x, y)
  out <- collect(step)

  expect_equal(
    show_query(step),
    expr(DT[, CJ(x, y, unique = TRUE)])
  )
  expect_equal(step$vars, c("x", "y"))
  expect_equal(nrow(out), 4)
})

test_that("multiple variables in one arg doesn't expand", {
  tbl <- tibble(x = 1:2, y = 1:2)
  dt <- lazy_dt(tbl, "DT")
  step <- expand(dt, c(x, y))
  out <- collect(step)

  expect_equal(nrow(out), 2)
})

test_that("works with unnamed vectors", {
  tbl <- tibble(x = 1:2, y = 1:2)
  dt <- lazy_dt(tbl, "DT")
  step <- expand(dt, x, 1:2)
  out <- collect(step)

  expect_equal(
    show_query(step),
    # expr(unique(DT[, .(x = x, V2 = 1:2)])[CJ(x, V2, unique = TRUE), on = .(x, V2)])
    expr(DT[, CJ(x, 1:2, unique = TRUE)][, .(x, `1:2` = V2)])
  )
  expect_equal(step$vars, c("x", "1:2"))
  expect_equal(nrow(out), 4)
})

test_that("works with named vectors", {
  tbl <- tibble(x = 1:2, y = 1:2)
  dt <- lazy_dt(tbl, "DT")
  step <- expand(dt, x, val = 1:2)
  out <- collect(step)

  expect_equal(
    show_query(step),
    # expr(unique(DT[, .(x = x, val = 1:2)])[CJ(x, val, unique = TRUE), on = .(x, val)])
    expr(DT[, CJ(x, val = 1:2, unique = TRUE)])
  )
  expect_equal(step$vars, c("x", "val"))
  expect_equal(nrow(out), 4)
})

test_that("expand respects groups", {
  tbl <- tibble(
    a = c(1L, 1L, 2L),
    b = c(1L, 2L, 1L),
    c = c(2L, 1L, 1L)
  )
  dt <- lazy_dt(tbl, "DT")
  step <- dt %>% group_by(c) %>% expand(a, b)
  out <- collect(step)

  expect_equal(
    show_query(step),
    expr(unique(DT[, .(c, a, b)])[, .SD[CJ(a, b, unique = TRUE), on = .(a, b)], keyby = .(c)])
  )
  expect_equal(step$vars, c("c", "a", "b"))
  expect_equal(out$a, c(1, 1, 2, 2, 1))
  expect_equal(out$b, c(1, 2, 1, 2, 1))
})

test_that("NULL inputs", {
  tbl <- tibble(x = 1:5)
  dt <- lazy_dt(tbl, "DT")
  step <- expand(dt, x, y = NULL)
  out <- collect(step)
  expect_equal(out, tbl)
})

test_that("expand respects .name_repair", {
  dt <- lazy_dt(tibble(x = 1:2), "DT")

  suppressMessages(
    expect_named(dt %>% expand(x, x, .name_repair = "unique") %>% collect(), c("x...1", "x...2"))
  )
})
