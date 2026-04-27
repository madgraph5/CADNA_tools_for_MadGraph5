//
// Created by Frantisek Stloukal on 14.11.2025.
//

#ifndef CPPPROCESS_STANDALONE_COMPLEX_H
#define CPPPROCESS_STANDALONE_COMPLEX_H
#include <complex>
#include "typeTraits.h"



// The number of floating point types in a complex type (real, imaginary)
namespace mgOnGpu
{
    constexpr int nx2 = 2;
    constexpr int cppAlign = 64;
}

#if defined (__CADNA__)
//CADNA operator overload
template <typename T>
constexpr bool is_special_fp_v =
    std::is_same_v<T, double_st> || std::is_same_v<T, float_st>;
#endif

// --- Type definition (simple complex type derived from cxtype_v)
template <typename FP>
class cxsmpl
{
public:
    constexpr cxsmpl() : m_real(0), m_imag(0)
    {
    }

    cxsmpl(const cxsmpl&) = default;
    cxsmpl(cxsmpl&&) = default;

    constexpr cxsmpl(const FP& r, const FP& i = 0) : m_real(r), m_imag(i)
    {
    }

    constexpr cxsmpl(const std::complex<FP>& c) : m_real(c.real()), m_imag(c.imag())
    {
    }

    cxsmpl& operator=(const cxsmpl&) = default;
    cxsmpl& operator=(cxsmpl&&) = default;

    constexpr cxsmpl& operator+=(const cxsmpl& c)
    {
        m_real += c.real();
        m_imag += c.imag();
        return *this;
    }

    constexpr cxsmpl& operator-=(const cxsmpl& c)
    {
        m_real -= c.real();
        m_imag -= c.imag();
        return *this;
    }

    constexpr const FP& real() const { return m_real; }
    constexpr const FP& imag() const { return m_imag; }

    template <typename FP2>
    constexpr explicit operator cxsmpl<FP2>() const { return cxsmpl<FP2>(static_cast<FP2>(m_real), static_cast<FP2>(m_imag)); }
private:
    FP m_real, m_imag; // RI
};

template< typename T >
struct rne
{
   T sum;
   T error;
};

template< typename T, std::enable_if_t< std::is_floating_point_v< T >
#if defined (__CADNA__)
|| is_special_fp_v<T>
#endif
, int > = 0 >
constexpr  inline rne< T >
quick_two_sum( const T a, const T b )
{
  const T s = a + b;
  const T z = s -a;
  const T err = b -z;
  return {s, err};
}

template< typename T, std::enable_if_t< std::is_floating_point_v< T >
#if defined (__CADNA__)
|| is_special_fp_v<T>
#endif
, int > = 0 >
constexpr rne< T >
two_sum( const T a, const T b )
{
    const T s =  a + b;
    const T aa = s -b;
    const T bb = s -aa;
    const T da = a -aa;
    const T db = b -bb;
    const T err = da + db;
    return {s, err};
}

template<typename FP>
class cxcomp
{
    FP m_real;
    FP m_imag;
    FP m_real_err;
    FP m_imag_err;

    public:

    constexpr cxcomp() : m_real(0), m_imag(0),
     m_real_err(0), m_imag_err(0)
    {
    }

    cxcomp(const cxcomp&) = default;
    cxcomp(cxcomp&&) = default;

    constexpr cxcomp(const FP& r, const FP& i = 0, const FP& re = 0.f, const FP& ie = 0.f) : m_real(r), m_imag(i), m_real_err(re), m_imag_err(ie)
    {
    }

    constexpr cxcomp(const std::complex<FP>& c) : m_real(c.real()), m_imag(c.imag()), m_real_err(0), m_imag_err(0)
    {
    }

    cxcomp& operator=(const cxcomp&) = default;
    cxcomp& operator=( cxcomp&&) = default;

    /*cxcomp& operator=(const cxsmpl<FP>& c)
    {
        m_real = c.real();
        m_imag = c.imag();
        m_real_err = 0.f;
        m_imag_err = 0.f;
        return *this;
    };
    */

    /*constexpr cxcomp& operator+=(const cxsmpl<FP>& c)
    {
        rne< FP > r_real = two_sum( m_real, c.real() );
        rne< FP > r_imag = two_sum( m_imag, c.imag() );
        m_real = r_real.sum;
        m_real_err += r_real.error;
        m_imag = r_imag.sum;
        m_imag_err += r_imag.error;
        return *this;
    }

    constexpr cxcomp& operator-=(const cxsmpl<FP>& c)
    {
        rne< FP > r_real = two_sum( m_real, -c.real() );
        rne< FP > r_imag = two_sum( m_imag, -c.imag() );
        m_real = r_real.sum;
        m_real_err += r_real.error;
        m_imag = r_imag.sum;
        m_imag_err += r_imag.error;
        return *this;
    }*/

    template<typename FP2>
    constexpr cxcomp& operator+=(const cxsmpl<FP2>& c)
        {
            m_real += static_cast<FP>(c.real());
            m_imag += static_cast<FP>(c.imag());
            return *this;
        }

    template<typename FP2>
    constexpr cxcomp& operator-=(const cxsmpl<FP2>& c)
        {
            m_real -= static_cast<FP>(c.real());
            m_imag -= static_cast<FP>(c.imag());
            return *this;
        }


    template <typename FP2>
    cxcomp& operator=(const cxsmpl<FP2> c )
    {
        m_real = static_cast<FP>(c.real());
        m_imag = static_cast<FP>(c.imag());
        return *this;
    }

    constexpr const FP& real() const { return m_real; }
    constexpr const FP& imag() const { return m_imag; }

    //template <typename FP2>
    //constexpr explicit operator cxcomp<FP2>() const { return cxcomp<FP2>(m_real, m_imag); }

    template<typename FP2>
    constexpr cxsmpl<FP2> finalize() const
    {
        //return cxsmpl<FP>(m_real+m_real_err, m_imag+m_imag_err);
        return cxsmpl<FP2>(static_cast<FP2>(m_real), static_cast<FP2>(m_imag));
    }

    template<typename FP2>
    explicit operator cxsmpl<FP2>() const { return finalize<FP2>(); }

};

template <typename FP>
constexpr
inline cxsmpl<FP>
conj(const cxsmpl<FP>& c)
{
    return cxsmpl<FP>(c.real(), -c.imag());
}

template <typename FP>
inline std::ostream&
operator<<(std::ostream& out, const cxsmpl<FP>& c)
{
    out << "(" << c.real() << ", " << c.imag() << ")"; // add a space after the comma
    return out;
}

// Operators for cxsmpl
template <typename FP>
inline
constexpr cxsmpl<FP>
operator+(const cxsmpl<FP> a)
{
    return a;
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator-(const cxsmpl<FP>& a)
{
    return cxsmpl<FP>(-a.real(), -a.imag());
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator+(const cxsmpl<FP>& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a.real() + b.real(), a.imag() + b.imag());
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator+(const FP& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a, 0) + b;
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator-(const cxsmpl<FP>& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a.real() - b.real(), a.imag() - b.imag());
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator-(const FP& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a, 0) - b;
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator*(const cxsmpl<FP>& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a.real() * b.real() - a.imag() * b.imag(), a.imag() * b.real() + a.real() * b.imag());
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator*(const FP& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a, 0) * b;
}

inline
constexpr cxsmpl<float>
operator*(const double& a, const cxsmpl<float>& b)
{
    return cxsmpl<float>(a, 0) * b;
}

inline
constexpr cxsmpl<float>
operator*(const cxsmpl<float>& a, const double& b)
{
    return a * cxsmpl<float>(b, 0);
}

inline
constexpr cxsmpl<double>
operator*(const float& a, const cxsmpl<double>& b)
{
    return cxsmpl<double>(a, 0) * b;
}

inline
constexpr cxsmpl<double>
operator*(const cxsmpl<double>& a, const float& b)
{
    return a * cxsmpl<double>(b, 0);
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator/(const cxsmpl<FP>& a, const cxsmpl<FP>& b)
{
    FP bnorm = b.real() * b.real() + b.imag() * b.imag();
    return cxsmpl<FP>((a.real() * b.real() + a.imag() * b.imag()) / bnorm,
                      (a.imag() * b.real() - a.real() * b.imag()) / bnorm);
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator/(const FP& a, const cxsmpl<FP>& b)
{
    return cxsmpl<FP>(a, 0) / b;
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator+(const cxsmpl<FP>& a, const FP& b)
{
    return a + cxsmpl<FP>(b, 0);
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator-(const cxsmpl<FP>& a, const FP& b)
{
    return a - cxsmpl<FP>(b, 0);
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator*(const cxsmpl<FP>& a, const FP& b)
{
    return a * cxsmpl<FP>(b, 0);
}

template <typename FP>
inline
constexpr cxsmpl<FP>
operator/(const cxsmpl<FP>& a, const FP& b)
{
    return a / cxsmpl<FP>(b, 0);
}



#if defined (__CADNA__)

inline
cxsmpl<double_st>
operator/(const cxsmpl<double_st>& a, const float_st& b)
{
    return a / cxsmpl<double_st>(static_cast<double_st>(b), 0);
}

template <typename FP, typename FP2,
          std::enable_if_t<is_special_fp_v<FP> || is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator+(const cxsmpl<FP>& a, const cxsmpl<FP2>& b)
{
    if constexpr (is_special_fp_v<FP>)
    {
        cxsmpl<FP> b_temp = b;
        return cxsmpl<FP>(a.real() + b_temp.real(), a.imag() + b_temp.imag());
    }
    else
    {
        cxsmpl<FP2> a_temp = a;
        return cxsmpl<FP2>(a_temp.real() + b.real(), a_temp.imag() + b.imag());
    }
}

template <typename FP, typename FP2,
          std::enable_if_t<is_special_fp_v<FP> || is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator-(const cxsmpl<FP>& a, const cxsmpl<FP2>& b)
{
    if constexpr (is_special_fp_v<FP>)
    {
        cxsmpl<FP> b_temp = b;
        return cxsmpl<FP>(a.real() - b_temp.real(), a.imag() - b_temp.imag());
    }
    else
    {
        cxsmpl<FP2> a_temp = a;
        return cxsmpl<FP2>(a_temp.real() - b.real(), a_temp.imag() - b.imag());
    }
}

template <typename FP, typename FP2,
          std::enable_if_t<is_special_fp_v<FP> || is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator*(const cxsmpl<FP>& a, const cxsmpl<FP2>& b)
{
    if constexpr (is_special_fp_v<FP>)
    {
        cxsmpl<FP> b_temp = b;
        return cxsmpl<FP>(a.real() * b_temp.real() - a.imag() * b_temp.imag(),
                          a.imag() * b_temp.real() + a.real() * b_temp.imag());
    }
    else
    {
        cxsmpl<FP2> a_temp = a;
        return cxsmpl<FP2>(a_temp.real() * b.real() - a_temp.imag() * b.imag(),
                           a_temp.imag() * b.real() + a_temp.real() * b.imag());
    }
}

template <typename FP, typename FP2,
          std::enable_if_t<is_special_fp_v<FP> || is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator/(const cxsmpl<FP>& a, const cxsmpl<FP2>& b)
{
    if constexpr (is_special_fp_v<FP>)
    {
        cxsmpl<FP> b_temp = b;
        FP bnorm = b_temp.real() * b_temp.real() + b_temp.imag() * b_temp.imag();
        return cxsmpl<FP>((a.real() * b_temp.real() + a.imag() * b_temp.imag()) / bnorm,
                          (a.imag() * b_temp.real() - a.real() * b_temp.imag()) / bnorm);
    }
    else
    {
        cxsmpl<FP2> a_temp = a;
        FP2 bnorm = b.real() * b.real() + b.imag() * b.imag();
        return cxsmpl<FP2>((a_temp.real() * b.real() + a_temp.imag() * b.imag()) / bnorm,
                           (a_temp.imag() * b.real() - a_temp.real() * b.imag()) / bnorm);
    }
}

template <typename FP, typename FP2,
         std::enable_if_t<is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator*(const FP& a, const cxsmpl<FP2>& b)
{
    return cxsmpl<FP2>(static_cast<FP2>(a), 0) * b;
}

template <typename FP, typename FP2,
    std::enable_if_t<is_special_fp_v<FP>, int> = 0>
inline constexpr auto
operator *(const cxsmpl<FP>& a, const FP2& b)
{
    return a * cxsmpl<FP>(b, 0);
}

template <typename FP, typename FP2,
         std::enable_if_t<is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
operator/(const FP& a, const cxsmpl<FP2>& b)
{
    return cxsmpl<FP2>(static_cast<FP2>(a), 0) / b;
}

template <typename FP, typename FP2,
    std::enable_if_t<is_special_fp_v<FP>, int> = 0>
inline constexpr auto
operator /(const cxsmpl<FP>& a, const FP2& b)
{
    return a / cxsmpl<FP>(b, 0);
}


#endif

#ifdef __CADNA__
template <typename FP, typename FP2,
          std::enable_if_t<std::is_same_v<FP, double_st> || std::is_same_v<FP2,double_st>, int> = 0>
inline auto
cxmake( const FP& r, const FP2& i )
{
        if constexpr (std::is_same_v<FP, double_st>)
            return cxsmpl<FP>( r, static_cast<FP>(i) ); // cxsmpl constructor
        else if constexpr (std::is_same_v<FP2, double_st>)
            return cxsmpl<FP2>( static_cast<FP2>(r), i ); // cxsmpl constructor
}

/*template <typename FP, typename FP2,
    std::enable_if_t<is_special_fp_v<FP> and !is_special_fp_v<FP2>, int> = 0>
inline constexpr auto
  cxmake( const cxsmpl<FP2>& c ) // cxsmpl to cxtype (double-float to double_st-float_st)
  {
        return cxsmpl<FP>( c.real(), c.imag() );
  }*/
#endif

template <typename FP>
inline cxsmpl<FP>
cxmake( const FP& r, const FP& i )
{
      return cxsmpl<FP>( r, i ); // cxsmpl constructor
}

/*template <typename FP>
inline cxsmpl<FP>
cxmake(  cxsmpl<FP> a)
{
      return a;
}*/

template <typename FP>
inline FP
cxreal( const cxsmpl<FP>& c )
{
    return c.real(); // cxsmpl::real()
}

template <typename FP>
inline FP
cximag( const cxsmpl<FP>& c )
{
    return c.imag(); // cxsmpl::imag()
}

template <typename FP>
inline cxsmpl<FP>
cxconj( const cxsmpl<FP>& c )
{
    return conj( c ); // conj( cxsmpl )
}

inline cxtype                 // NOT __device__
cxmake( const std::complex<float>& c ) // std::complex to cxsmpl (float-to-float or float-to-double)
{
    return cxmake<fptype>( c.real(), c.imag() );
}

inline cxtype                  // NOT __device__
cxmake( const std::complex<double>& c ) // std::complex to cxsmpl (double-to-float or double-to-double)
{
    return cxmake<fptype>( c.real(), c.imag() );
}

inline cxtype                  // NOT __device__
cxmake( const cxtype c ) // std::complex to cxsmpl (double-to-float or double-to-double)
{
    return cxmake<fptype>( c.real(), c.imag() );
}

template <typename FP, typename  FP2>
inline cxsmpl<FP>                  // NOT __device__
cxmake( const cxsmpl<FP2> c ) // std::complex to cxsmpl (double-to-float or double-to-double)
{
    return cxmake<FP>( c.real(), c.imag() );
}

class cxtype_ref
{
public:
    cxtype_ref() = delete;
    cxtype_ref( const cxtype_ref& ) = delete;
    cxtype_ref( cxtype_ref&& ) = default; // copy const refs
    cxtype_ref( fptype& r, fptype& i )
      : m_preal( &r ), m_pimag( &i ) {} // copy (create from) const refs
    cxtype_ref& operator=( const cxtype_ref& ) = delete;
    cxtype_ref& operator=( const cxtype& c )
    {
        *m_preal = cxreal( c );
        *m_pimag = cximag( c );
        return *this;
    } // copy (assign) non-const values
    operator cxtype() const { return cxmake( *m_preal, *m_pimag ); }
private:
    fptype* const m_preal; // const pointer to non-const fptype R
    fptype* const m_pimag; // const pointer to non-const fptype I
};

// Printout to stream for user defined types
inline std::ostream&
operator<<( std::ostream& out, const cxtype_ref& c )
{
    out << (cxtype)c;
    return out;
}

template<typename T>
inline cxsmpl<T> cxzero() { return cxsmpl<T>( 0.f, 0.f ); }

inline fptype_sv
cxabs2( const cxtype_sv& c )
{
    return cxreal( c ) * cxreal( c ) + cximag( c ) * cximag( c );
}
#endif //CPPPROCESS_STANDALONE_COMPLEX_H
