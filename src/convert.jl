#sigmoid number conversions.

#let's put these functions here. We'll move them later.
import Base.convert

const IEEEFloat = Union{Float16, Float32, Float64}

function convert{N, ES, mode, I <: Signed}(T::Type{Sigmoid{N, ES, mode}}, int::I)
  #warn("conversion from integers not yet properly supported! $int")
  #throw(ErrorException("halp"))
  convert(T, convert(Float64, int))
end

@generated function convert{F <: IEEEFloat, N, ES, mode}(::Type{F}, x::Sigmoid{N, ES, mode})
  FInt  = Dict(Float16 => UInt16, Float32 => UInt32, Float64 => UInt64)[F]
  fbits = Dict(Float16 => 16    , Float32 => 32,     Float64 => 64)[F]
  ebits = Dict(Float16 => 5     , Float32 => 8,      Float64 => 11)[F]
  bias = (1 << (ebits - 1)) -1
  quote
    #check for two dropout values.
    (reinterpret((@UInt), x) == zero(@UInt)) && return zero(F)
    isfinite(x) || return F(Inf)

    #magically generate the subproperties of x.
    @breakdown x

    FP_sign = (($FInt)(x_sgn) << ($fbits - 1))

    #calculate the biased exponent for conversion to IEEE FP
    FP_biased_exponent::$FInt = ($bias + x_exp) << ($fbits - $ebits - 1)

    #convert to UInt64 and move the fraction even more (or back, if we started as a 64-bit int.)
    if $fbits < __BITS
      FP_fraction = ($FInt)(x_frc >> (($ebits + 1) + (__BITS - $fbits)))
    else
      FP_fraction = ($FInt)(x_frc) >> (($ebits + 1) - (($fbits) - __BITS))
    end

    #put the parts together and reassign as a Floating point.
    reinterpret(F, FP_sign | FP_biased_exponent | FP_fraction)
  end
end

doc"""
  fptrip(x)

  takes an IEEE floating point and returns the triplet (sign::Bool, exponent::Int, fraction::@UInt).
  this will then be used to generate the fractional value.

  NB: Doesn't work for Inf and zero values.
"""
@generated function fptrip{F <: IEEEFloat}(x::F)
  FInt  = Dict(Float16 => UInt16, Float32 => UInt32, Float64 => UInt64)[F]
  fbits = Dict(Float16 => 16    , Float32 => 32,     Float64 => 64)[F]
  ebits = Dict(Float16 => 5     , Float32 => 8,      Float64 => 11)[F]
  bias = (1 << (ebits - 1)) -1
  quote
    #first grab the sign bit.
    sign = (x < 0)
    #flip the sign.
    x = sign ? -x : x
    intform = reinterpret($FInt, x) & ((zero($FInt) - 1) >> 1)
    exponent = Int(intform >> ($fbits - $ebits - 1)) - $bias
    if $fbits < __BITS
      #convert to left-shifted form of the fraction, then expand, then shift more.
      fraction = ((@UInt)(intform << ($ebits + 1))) << (__BITS - $fbits)
    else
      #convert to the left-shifted but then go all the way over, then convert to @UInt
      fraction = (@UInt)(intform << ($ebits + 1) - (__BITS - $fbits))
    end

    (sign, exponent, fraction)
  end
end

function convert{N, ES, mode, F <: IEEEFloat}(::Type{Sigmoid{N, ES, mode}}, f::F)
  #handle the three corner cases of NaN, infinity and zero.
  isnan(f) && throw(NaNError(convert, [Sigmoid{N, ES, mode}, f]))
  isfinite(f) || return reinterpret(Sigmoid{N, ES, mode}, @signbit)
  (f == zero(F)) && return reinterpret(Sigmoid{N, ES, mode}, zero(@UInt))
  #retrieve the floating point triplet.
  __round(build_numeric(Sigmoid{N, ES, mode}, fptrip(f)...))
end

@generated function (::Type{Sigmoid{N, ES, mode}}){N, ES, mode, UI <: Unsigned}(i::UI)
  #conversion from unsigned integer will be interpreted as a desire to convert
  #logical representation; conversion from signed integer will be interpreted
  #as a desire to convert the semantic value.

  #first check to see that the number of bits in the sigmoid is less than the
  #number of bits in the unsigned integer.
  int_length = sizeof(i) * 8
  (N <= int_length) || throw(ArgumentError("insufficient bits in source integer to represent the sigmoid number."))
  quote
    #assume that the integer representation is right-aligned.  We're going to want
    #to move that to the LEFT.  First convert the value to the appropriate integer
    #type based on the global integer size, then shift right the appropriate number
    #of bits, then reinterpret it as a sigmoid number.
    reinterpret(Sigmoid{N, ES, mode}, (@UInt)(i) << (__BITS - N))
  end
end

function build_numeric{N, ES, mode}(::Type{Sigmoid{N, ES, mode}}, sign, exponent, fraction)
  if exponent < 0
    (regime, subexponent) = divrem(exponent, 1 << ES)
    if (subexponent != 0)
      regime -= 1
      subexponent += 1 << ES
    end

    fshift = -regime + 2 + ES

    body = (one(@UInt) << ES) | subexponent

    body <<= (__BITS + regime - 2 - ES)
  else
    (regime, subexponent) = divrem(exponent, 1 << ES)

    #set the prefix.  That's 2^regime - 1
    body = (((one(@UInt) << (regime + 1)) - 1) << (ES + 1)) + subexponent

    #shift the prefix over
    body <<= (__BITS - regime - 3 - ES)

    fshift = regime + 3 + ES
  end

  absval = body | (fraction >> fshift)

  reinterpret(Sigmoid{N, ES, mode}, sign ? -absval : absval)
end

#build_numeric is much simpler when ES = 0
function build_numeric{N, mode}(::Type{Sigmoid{N, 0, mode}}, sign, exponent, fraction)
  if exponent < 0
    fshift = -exponent + 2
    body = one(@UInt) << (__BITS + exponent - 2)
  else
    #set the prefix.  That's 2^exponent - 1
    prefix = (one(@UInt) << (exponent + 1)) - 1
    #shift the prefix over
    body = prefix << (__BITS - exponent - 2)
    fshift = exponent + 3
  end

  absval = body | (fraction >> fshift)

  reinterpret(Sigmoid{N, 0, mode}, sign ? -absval : absval)
end

#build_arithmetic is restricted to ES == 0 sigmoids.
function build_arithmetic{N, mode}(::Type{Sigmoid{N, 0, mode}}, sign, exponent, fraction)
  normal = (fraction & @signbit) != 0
  #check if it's denormal.  If it is, then we don't shift.
  fshift = normal * (exponent + 1) + 1
  #set the prefix.  That's 2^exponent - 1
  prefix = (one(@UInt) << (exponent + 1)) - 1

  body = normal * (prefix << (__BITS - exponent - 2))

  absval = body | ((fraction & ((@signbit) - 1)) >> fshift)

  reinterpret(Sigmoid{N, 0, mode}, sign ? -absval : absval)
end

Base.promote_rule{T<:Sigmoid}(::Type{T}, ::Type{Int64}) = T
