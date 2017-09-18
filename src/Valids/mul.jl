function Base.:*{N,ES}(lhs::Valid{N,ES}, rhs::Valid{N,ES})
    (isempty(lhs)    || isempty(rhs))    && (return Valid{N,ES}(∅))
    (isallreals(lhs) || isallreals(rhs)) && (return Valid{N,ES}(ℝp))

    if roundsinf(lhs)
        infmul(lhs, rhs)
    elseif roundsinf(rhs)
        infmul(rhs, lhs)
    elseif containszero(lhs)
        zeromul(lhs, rhs)
    elseif containszero(rhs)
        zeromul(rhs, lhs)
    else
        stdmul(rhs, lhs)
    end
end

const __LHS_POS_RHS_POS = 0
const __LHS_NEG_RHS_POS = 1
const __LHS_POS_RHS_NEG = 2
const __LHS_NEG_RHS_NEG = 3

function infmul{N,ES}(lhs::Valid{N,ES}, rhs::Valid{N,ES})
    if containszero(rhs)
        return Valid{N,ES}(ℝp)
    elseif containszero(lhs)  #lhs contains zero AND infinity
        roundsinf(rhs) && return Valid{N,ES}(ℝp)

        #=
        #at this juncture, the value lhs must round both zero and infinity, and
        #the value rhs must be a standard, nonflipped double interval that is only on
        #one side of zero.

        # (100, 1) * (3, 4)     -> (300, 4)    (l * l, u * u)
        # (100, 1) * (-4, -3)   -> (-4, -300)  (u * l, l * u)
        # (-1, -100) * (3, 4)   -> (-4, -300)  (l * u, u * l)
        # (-1, -100) * (-4, -3) -> (300, 4)    (u * u, l * l)
        =#

        _state = (@s(lhs.lower) < 0) * 1 + (@s(rhs.lower) < 0) * 2

        if _state == __LHS_POS_RHS_POS
            res = ((@lower lhs) * (@lower rhs)) → ((@upper lhs) * (@upper rhs))
        elseif (_state < __LHS_NEG_RHS_NEG)
            res = ((@upper lhs) * (@lower rhs)) → ((@lower lhs) * (@upper rhs))
        else   #state == 3
            res = ((@upper lhs) * (@upper rhs)) → ((@lower lhs) * (@lower rhs))
        end

        (@s prev(res.lower)) <= (@s res.upper) && (return Valid{N,ES}(ℝp))
        return res

    elseif roundsinf(rhs)  #now we must check if rhs rounds infinity.

        lower1 = (@lower lhs) * (@lower rhs)
        lower2 = isfinite(lhs.upper) && isfinite(rhs.upper) ? (@upper lhs) * (@upper rhs) : lower1

        #nb: this needs to be fixed!
        upper1 = (@lower lhs) * (@upper rhs)
        upper2 = isfinite(rhs.lower) ? (@upper lhs) * (@lower rhs) : upper1

        min(lower1, lower2) → max(upper1, upper2)
    else
        #the last case is if lhs rounds infinity but rhs is a "well-behaved" value.
        #canonical example:
        # (2, -3) * (5, 7) -> (10, -15)
        # (2, -3) * (-7, -5) -> (15, -10)

        if (rhs.lower >= zero(Vnum{N,ES}))
            #println("rhs positive case")

            #println("lower side1: ", (@upper lhs))
            #println("lower side2: ", (@upper rhs))

            #println("lower: ", ((@upper lhs) * (@upper rhs)))
            #println("upper: ", ((@lower lhs) * (@upper rhs)))
            ((@lower lhs) * (@lower rhs)) → ((@upper lhs) * (@lower rhs))
        else
            #println("rhs negative case")
            ((@upper lhs) * (@upper rhs)) → ((@lower lhs) * (@upper rhs))
        end
    end
end

__simple_roundszero{T <: Valid}(v::T) = ((@s v.lower) < 0) & ((@s v.upper) > 0)

function zeromul{N,ES}(lhs::Valid{N,ES}, rhs::Valid{N,ES})

  #lhs and rhs guaranteed to not cross infinity.  lhs guaranteed to contain zero.
  if __simple_roundszero(rhs)
     #=
    # when rhs spans zero, we have to check four possible endpoints.
    lower1 = __lower_mul(lhs.lower, rhs.upper)
    lower2 = __lower_mul(lhs.upper, rhs.lower)
    upper1 = __upper_mul(lhs.lower, rhs.lower)
    upper2 = __upper_mul(lhs.upper, rhs.upper)

    return Valid{N,ES}(min(lower1, lower2), max(lower1, lower2))

    # in the case where the rhs doesn't span zero, we must only multiply by the
    # extremum.
    =#
  elseif (@s rhs.lower) >= 0
    ((@lower lhs) * (@upper rhs)) → ((@upper lhs) * (@upper rhs))
  else #rhs must be negative
  end
end

function stdmul{N,ES}(lhs::Valid{N,ES}, rhs::Valid{N,ES})
  #both values are "reasonable."
  _state = (@s(lhs.lower) < 0) * 1 + (@s(rhs.lower) < 0) * 2

  if _state == __LHS_POS_RHS_POS
    ((@lower lhs) * (@lower rhs)) → ((@upper lhs) * (@upper rhs))
  elseif _state == __LHS_NEG_RHS_POS
    ((@lower lhs) * (@upper rhs)) → ((@upper lhs) * (@lower rhs))
  elseif _state == __LHS_POS_RHS_NEG
    ((@upper lhs) * (@lower rhs)) → ((@lower lhs) * (@upper rhs))
  else #__LHS_NEG_RHS_NEG
    ((@upper lhs) * (@upper rhs)) → ((@lower lhs) * (@lower rhs))
  end

end
