/*
 * JSON parser, yacc/bison based. Manual lexer.
 * Mikhail.
 */

%{
#include <tcl.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#if (TCL_MAJOR_VERSION > 8) || ((TCL_MAJOR_VERSION == 8) && (TCL_MINOR_VERSION > 4))
#define USE_DICT
#endif

#include <json_y.h>

#define TOKEN(tok)   TRACE (("TOKEN  %s\n", tok))
#define TOKEN1(tok)  TRACE (("TOKEN  %s (%s)\n", tok, Tcl_GetString(context->obj)))
#define REDUCE(rule) TRACE (("REDUCE %s\n", rule))

#define TRUE_O  staticobj(TRUEO)
#define FALSE_O staticobj(FALSEO)
#define NULL_O  staticobj(NULLO)

enum constants { FALSEO, TRUEO, NULLO, NUMCONSTANTS };
static Tcl_Obj * staticobj(enum constants);
static void jsonerror(struct context *, const char *);
static int  jsonlexp(struct context *context);

#define YYPARSE_PARAM_TYPE void *
#define YYPARSE_PARAM	   context
#define YYPARSE_PARAM_DECL

#define yylex()	     jsonlexp(context)
#define yyerror(msg) jsonerror(context, msg)

#ifndef YYBISON
static int yyparse(YYPARSE_PARAM_TYPE YYPARSE_PARAM);
#endif

%}

%union {
	Tcl_Obj		*obj;
	struct {
		Tcl_Obj	*key;
		Tcl_Obj	*val;
	} keyval;
};

%token STRING CONSTANT

%type <obj>	tree
%type <obj>	json
%type <obj>	object
%type <obj>	list
%type <obj>	values
%type <obj>	members
%type <obj>	value
%type <obj>	string
%type <keyval>	member

%%

tree    : json
	{
		struct context *c = context;
		REDUCE("TREE");
		if (c->I) {
		  Tcl_SetObjResult(c->I, $1);
		  TRACE (("  RESULT (%s)\n", Tcl_GetString($1)));
		}
		c->result = TCL_OK;
	}
	;

json    : value
	;

object	: '{' members '}'
	{
		$$ = $2;
	}
	| '{' '}'
	{
		$$ = Tcl_NewObj();
	}
	;

list	: '[' values ']'
	{
		$$ = $2;
	}
	| '[' ']'
	{
		$$ = Tcl_NewObj();
	}
	;

values	: value
	{	
		$$ = Tcl_NewListObj(1, &$1);
	}
	| values ',' value
	{
		Tcl_ListObjAppendElement(NULL, $1, $3);
		$$ = $1;
	}
	;

members	: member
	{
#ifdef USE_DICT
		$$ = Tcl_NewDictObj();
		Tcl_DictObjPut(NULL, $$, $1.key, $1.val);
#else
	        $$ = Tcl_NewListObj(0, NULL);
		Tcl_ListObjAppendElement(NULL, $$, $1.key);
		Tcl_ListObjAppendElement(NULL, $$, $1.val);
#endif
	}
	| members ',' member
	{
#ifdef USE_DICT
		Tcl_DictObjPut(NULL, $1, $3.key, $3.val);
#else
		Tcl_ListObjAppendElement(NULL, $1, $3.key);
		Tcl_ListObjAppendElement(NULL, $1, $3.val);
#endif
		$$ = $1;
	}
	;

member	: string ':' value
	{
		$$.key = $1;
		$$.val = $3;
	}
	;

string	: STRING
	{
		$$ = ((struct context *)context)->obj;
	}
	;

value	: CONSTANT
	{
		$$ = ((struct context *)context)->obj;
	}
	| string
	| object
	| list
	;

%%
void
jsonparse (struct context* context)
{
  yyparse (context);
}

#define HAVE(n) (context->remaining >= n)

#define DRAIN(n) context->text += n, context->remaining -= n

#define	STORESTRINGSEGMENT()				\
	if (initialized) {				\
		if (context->text != bp) {		\
			Tcl_AppendToObj(context->obj,	\
			    bp, context->text - bp);	\
		}					\
	} else {					\
		context->obj = Tcl_NewStringObj(	\
		    bp, context->text - bp);		\
		initialized = 1;			\
	}

void
jsonskip(struct context *context)
{
  while (context->remaining) {
    switch (*context->text) {
    case '\n':
    case ' ':
    case '\t':
    case '\r':
      DRAIN(1);
      continue;
    }
    break;
  }
}

/*
 * JSON has 3 string-literals: "null", "true", and "false". Instead of
 * creating a NEW Tcl-object EACH TIME such literal is encountered, we
 * return the reference to the first such object created (and bump its
 * reference-count to prevent memory errors).
 */
Tcl_Obj *
staticobj(enum constants constant)
{
    typedef struct ThreadSpecificData {
        Tcl_Obj* objects [NUMCONSTANTS];
    } ThreadSpecificData;

    static Tcl_ThreadDataKey dataKey;
    ThreadSpecificData *tsdPtr = 
        (ThreadSpecificData *) Tcl_GetThreadData (&dataKey,
						  sizeof (ThreadSpecificData));
    Tcl_Obj         **p;

    assert(constant >= 0 && constant < NUMCONSTANTS);
    p = tsdPtr->objects + constant;
    if (*p == NULL) {
	/*
	 * This is the first time we were asked for an object for
	 * this constant. Create it to the best of our ability.
	 *
	 * Using the trick below, rather than the usual
	 * Tcl_NewStringObj(), avoids creation of a COPY
	 * of the string "null". Such copying is a waste,
	 * if the object itself is never to be freed...
	 */
	*p = Tcl_NewObj();
	switch (constant) {
	case NULLO:
	    (*p)->bytes = (void *)"null";
	    (*p)->length = 4;
	    break;
	case TRUEO:
	    /*
	     * A boolean-object's default string representation is
	     * "0" or "1", but we'd like the fancier "false" and
	     * "true" for our objects to better match the
	     * expectations of JSON-users.
	     */
	    Tcl_SetBooleanObj(*p, 1);
	    (*p)->bytes = (void *)"true";
	    (*p)->length = 4;
	    break;
	case FALSEO:
	    Tcl_SetBooleanObj(*p, 0);
	    (*p)->bytes = (void *)"false";
	    (*p)->length = 5;
	    break;
	default:
	    Tcl_Panic("Internal error in %s:%d unknown constant %d",
		__FILE__, __LINE__, (int)constant);
	}
    }
    /*
     * Increase the ref-count so nothing ever attempts to free
     * neither the static object we are returning, nor its bytes.
     */
    Tcl_IncrRefCount(*p);
    return *p;
}

static int
jsonlexp(struct context *context)
{
  const char *bp = NULL;

  /* Question: Why not plain numbers 1,2 for the states
   *           but these specific hex patterns ?
   */
  enum {
    PLAIN	= 0x0000ff00,
    INSTR	= 0x00ff0000
  } lstate;
  double 	 d;
  int		 i;
  long	 	 l;
  long long	 ll;
  Tcl_WideInt	 wi;
#ifdef USE_BIG_NUM
  mp_int	 mpi;
#endif
  char		*end;
  const char	*p;
  int		 initialized = 0;

  /*
   * Do not auto-lex beyond a full json structure.
   */
  if (context->result == TCL_OK) {
    TOKEN ("<<eof>>");
    return 0;
  }

  /*
   * Quickly skip and ignore whitespace.
   */
  while (context->remaining) {
    switch (*context->text) {
    case '\n':
    case ' ':
    case '\t':
    case '\r':
      DRAIN(1);
      continue;
    }
    break;
  }

  /*
   * Handle the token following the whitespace. Small state machine to
   * handle strings and escapes in them, and bare words (various
   * contants, and numbers).
   */
  for (lstate = PLAIN; context->remaining > 0; DRAIN(1)) {
    if (lstate == INSTR) {
      if (*context->text == '"') {
	/*
	 * End of quoted string
	 */

	STORESTRINGSEGMENT();
	DRAIN(1);
	TOKEN1 ("STRING");
	return STRING;
      }

      if (*context->text == '\\') {
	/*
	 * Escaped sequence. The 9 sequences specified at json.org
	 * are:
	 *       \"  \\  \/  \b  \f  \n  \r  \t  \uXXXX
	 */
	char	buf[TCL_UTF_MAX];
	int	len, consumed;

	STORESTRINGSEGMENT();

	/*
	 * Perform additional checks to restrict the set of accepted
	 * escape sequence to what is allowed by json.org instead of
	 * Tcl_UtfBackslash.
	 */

	if (!HAVE(1)) {
	  Tcl_AppendToObj(context->obj, "\\", 1);
	  yyerror("incomplete escape at <<eof> error");
	  TOKEN("incomplete escape at <<eof>> error");
	  return -1;
	}
	switch (context->text[1]) {
	  case '"':
	  case '\\':
	  case '/':
	  case 'b':
	  case 'f':
	  case 'n':
	  case 'r':
	  case 't':
	    break;
	  case 'u':
	    if (!HAVE(5)) {
	      Tcl_AppendToObj(context->obj, "\\u", 2);
	      yyerror("incomplete escape at <<eof> error");
	      TOKEN("incomplete escape at <<eof>> error");
	      return -1;
	    }
	    break;
	  default:
	    Tcl_AppendToObj(context->obj, context->text + 1, 1);
	    yyerror("bad escape");
	    TOKEN("bad escape");
	    return -1;
	}

	/*
	 * XXX Tcl_UtfBackslash() may be more
	 * XXX permissive, than JSON standard.
	 * XXX But that may be a good thing:
	 * XXX "be generous in what you accept".
	 */
	len = Tcl_UtfBackslash(context->text,
			       &consumed, buf);
	DRAIN(consumed - 1);
	bp = context->text + 1;
	Tcl_AppendToObj(context->obj, buf, len);
      }
      continue;
    }

    switch (*context->text) {
    case ',':
    case '{':
    case ':':
    case '}':
    case '[':
    case ']':
      DRAIN(1);
      TOKEN (context->text[-1]);
      return context->text[-1];
    case 't':
      if ((context->remaining < 4) ||
	  strncmp("rue", context->text + 1, 3))
	goto bareword;
      DRAIN(4);
      context->obj = TRUE_O;
      TOKEN1 ("CONSTANT");
      return CONSTANT;
    case 'f':
      if ((context->remaining < 5) ||
	  strncmp("alse", context->text + 1, 4))
	goto bareword;
      DRAIN(5);
      context->obj = FALSE_O;
      TOKEN1 ("CONSTANT");
      return CONSTANT;
    case 'n':
      if ((context->remaining < 4) ||
	  strncmp("ull", context->text + 1, 3))
	goto bareword;
      DRAIN(4);
      context->obj = NULL_O;
      TOKEN1 ("CONSTANT");
      return CONSTANT;
    case '"':
      bp = context->text + 1;
      lstate = INSTR;
      continue;
    case '\\':
      yyerror("Escape character outside of string");
      TOKEN ("escape error");
      return -1;
    }

    context->obj = NULL;
    /*
     * We already considered the null, true, and false
     * above, so it can only be a number now.
     */
    errno = 0;
    d = strtod(context->text, &end);
    if (end == context->text || isnan(d) || isinf(d))
	goto bareword; /* Nothing parsed */
    if (context->text[0] == '0' && context->text[1] != '.') {
	yyerror("Leading zeros aren't allowed in JSON");
	TOKEN("Leading zero error");
	return -1;
    }
    if (errno == ERANGE) {
	/* Too large. Let TCL core deal with it */
	goto donewithnumber;
    }
    /* See, if there was anything other than digit there: */
    for (p = context->text; p != end; p++) {
	if ((*p >= '0' && *p <= '9') || *p == '+' || *p == '-')
	    continue;
	context->obj = Tcl_NewDoubleObj(d);
	goto donewithnumber;
    }
    /* Didn't find any non-digits, must be an integer: */
    errno = 0;
    ll = strtoll(context->text, &end, 10);
    if (errno == ERANGE) {
	/* Too large. Let TCL core deal with it */
	goto donewithnumber;
    }
    /* Find the right integer-type for this number */
    i = ll;	/* int ? */
    if (i == ll) {
	context->obj = Tcl_NewIntObj(i);
	goto donewithnumber;
    }
    l = ll;	/* long ? */
    if (l == ll) {
	context->obj = Tcl_NewLongObj(l);
	goto donewithnumber;
    }
    wi = ll;	/* Tcl_WideInt */
    if (wi == ll) {
	context->obj = Tcl_NewWideIntObj(wi);
	goto donewithnumber;
    }
  donewithnumber:
    if (context->obj == NULL) {
	context->obj = Tcl_NewStringObj(context->text,
					end - context->text);
    }
    context->remaining -= (end - context->text);
    context->text = end;
    TOKEN1 ("CONSTANT");
    return CONSTANT;
  }

  TOKEN ("<<eof>>");
  return 0;
 bareword:
  yyerror("Bare word encountered");
  TOKEN ("bare word error");
  return -1;
}

#if 0
int
jsonlex(struct context *context)
{
  const char *bp = NULL;

  /* Question: Why not plain numbers 1,2 for the states
   *           but these specific hex patterns ?
   */
  enum {
    PLAIN	= 0x0000ff00,
    INSTR	= 0x00ff0000
  } lstate;
  double 	 d;
  char		*end;
  const char	*p;
  int		 initialized = 0;

  while (context->remaining) {
    /* Iterate over the whole string and check all tokens.
     * Nothing else.
     */

    /*
     * Quickly skip and ignore whitespace.
     */
    while (context->remaining) {
      switch (*context->text) {
      case '\n':
      case ' ':
      case '\t':
      case '\r':
	DRAIN(1);
	continue;
      }
      break;
    }

  /*
   * Handle the token following the whitespace. Small state machine to
   * handle strings and escapes in them, and bare words (various
   * contants, and numbers).
   */
  for (lstate = PLAIN; context->remaining > 0; DRAIN(1)) {
    if (lstate == INSTR) {
      if (*context->text == '"') {
	/*
	 * End of quoted string
	 */
	DRAIN(1);
	goto next_token;
      }

      if (*context->text == '\\') {
	/*
	 * Escaped sequence
	 */
	char	buf[TCL_UTF_MAX];
	int	len, consumed;

	/*
	 * XXX Tcl_UtfBackslash() may be more
	 * XXX permissive, than JSON standard.
	 * XXX But that may be a good thing:
	 * XXX "be generous in what you accept".
	 */
	len = Tcl_UtfBackslash(context->text, &consumed, buf);
	DRAIN(consumed - 1);
      }
      continue;
    }

    switch (*context->text) {
    case ',':
    case '{':
    case ':':
    case '}':
    case '[':
    case ']':
      DRAIN(1);
      goto next_token;

    case 't':
      if ((context->remaining < 4) ||
	  strncmp("rue", context->text + 1, 3))
	return -1; /* bare word */
      DRAIN(4);
      goto next_token;
    case 'f':
      if ((context->remaining < 5) ||
	  strncmp("alse", context->text + 1, 4))
	return -1; /* bare word */
      DRAIN(5);
      goto next_token;
    case 'n':
      if ((context->remaining < 4) ||
	  strncmp("ull", context->text + 1, 3))
	return -1; /* bare word */
      DRAIN(4);
      goto next_token;
    case '"':
      bp = context->text + 1;
      lstate = INSTR;
      continue;
    case '\\':
      /* Escape outside string, abort. */
      return -1;
    }

    /*
     * We already considered the null, true, and false
     * above, so it can only be a number now.
     *
     * NOTE: At this point we do not care about double
     * versus integer, nor about the possible integer
     * range. We generate a plain string Tcl_Obj and leave
     * it to the user of the generated structure to
     * convert to a number when actually needed. This
     * defered conversion also ensures that the Tcl and
     * platform we are building against does not matter
     * regarding integer range, only the abilities of the
     * Tcl at runtime.
     */

    d = strtod(context->text, &end);
    if (end == context->text)
      return -1; /* bare word */

    context->remaining -= (end - context->text);
    context->text = end;
    goto next_token;
  }

  return 0;

  next_token:
  continue;
  }
}
#endif

static void
jsonerror(struct context *context, const char *message)
{
  char *fullmessage;
  char *yytext;
  int   yyleng;

  if (context->has_error) return;

  if (context->obj) {
    yytext = Tcl_GetStringFromObj(context->obj, &yyleng);
    fullmessage = Tcl_Alloc(strlen(message) + 63 + yyleng);

    sprintf(fullmessage, "%s %d bytes before end, around ``%.*s''",
	    message, context->remaining, yyleng, yytext);
  } else {
    fullmessage = Tcl_Alloc(strlen(message) + 63);

    sprintf(fullmessage, "%s %d bytes before end",
	    message, context->remaining);
  }

  TRACE ((">>> %s\n",fullmessage));
  Tcl_SetResult    (context->I, fullmessage, TCL_DYNAMIC);
  Tcl_SetErrorCode (context->I, "JSON", "SYNTAX", NULL);
  context->has_error = 1;
}
