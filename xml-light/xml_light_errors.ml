type error_pos = {
	eline : int;
	eline_start : int;
	emin : int;
	emax : int;
}

type xml_error_msg =
	| UnterminatedComment
	| UnterminatedString
	| UnterminatedEntity
	| IdentExpected
	| CloseExpected
	| NodeExpected
	| AttributeNameExpected
	| AttributeValueExpected
	| EndOfTagExpected of string
	| EOFExpected

type xml_error = xml_error_msg * error_pos

(* xml errors *)
exception Xml_error of xml_error
exception File_not_found of string


(* dtd errors *)

type dtd_parse_error_msg =
	| InvalidDTDDecl
	| InvalidDTDElement
	| InvalidDTDAttribute
	| InvalidDTDTag
	| DTDItemExpected

type dtd_check_error =
	| ElementDefinedTwice of string
	| AttributeDefinedTwice of string * string
	| ElementEmptyContructor of string
	| ElementReferenced of string * string
	| ElementNotDeclared of string
	| WrongImplicitValueForID of string * string

type dtd_prove_error =
	| UnexpectedPCData
	| UnexpectedTag of string
	| UnexpectedAttribute of string
	| InvalidAttributeValue of string
	| RequiredAttribute of string
	| ChildExpected of string
	| EmptyExpected
	| DuplicateID of string
	| MissingID of string

type dtd_parse_error = dtd_parse_error_msg * error_pos

exception Dtd_parse_error of dtd_parse_error
exception Dtd_check_error of dtd_check_error
exception Dtd_prove_error of dtd_prove_error
