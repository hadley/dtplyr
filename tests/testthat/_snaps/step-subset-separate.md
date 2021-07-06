# checks type of `into` and `sep`

    Code
      separate(dt, x, "x", FALSE)
    Error <simpleError>
      is.character(sep) is not TRUE

---

    Code
      separate(dt, x, FALSE)
    Error <simpleError>
      is.character(into) is not TRUE

