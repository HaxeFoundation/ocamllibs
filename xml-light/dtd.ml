(*
 * Xml Light, an small Xml parser/printer with DTD support.
 * Copyright (C) 2003 Nicolas Cannasse (ncannasse@motion-twin.com)
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library has the special exception on linking described in file
 * README.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301 USA
 *)

open Xml_light_types
open Xml_light_utils
open Printf

type parse_error_msg = Xml_light_errors.dtd_parse_error_msg =
	| InvalidDTDDecl
	| InvalidDTDElement
	| InvalidDTDAttribute
	| InvalidDTDTag
	| DTDItemExpected

type check_error = Xml_light_errors.dtd_check_error =
	| ElementDefinedTwice of string
	| AttributeDefinedTwice of string * string
	| ElementEmptyContructor of string
	| ElementReferenced of string * string
	| ElementNotDeclared of string
	| WrongImplicitValueForID of string * string

type prove_error = Xml_light_errors.dtd_prove_error =
	| UnexpectedPCData
	| UnexpectedTag of string
	| UnexpectedAttribute of string
	| InvalidAttributeValue of string
	| RequiredAttribute of string
	| ChildExpected of string
	| EmptyExpected
	| DuplicateID of string
	| MissingID of string

type dtd_child = Xml_light_types.dtd_child =
	| DTDTag of string
	| DTDPCData
	| DTDOptional of dtd_child
	| DTDZeroOrMore of dtd_child
	| DTDOneOrMore of dtd_child
	| DTDChoice of dtd_child list
	| DTDChildren of dtd_child list

type dtd_element_type = Xml_light_types.dtd_element_type =
	| DTDEmpty
	| DTDAny
	| DTDChild of dtd_child

type dtd_attr_default = Xml_light_types.dtd_attr_default =
	| DTDDefault of string
	| DTDRequired
	| DTDImplied
	| DTDFixed of string

type dtd_attr_type = Xml_light_types.dtd_attr_type =
	| DTDCData
	| DTDNMToken
	| DTDEnum of string list
	| DTDID
	| DTDIDRef

type dtd_item = Xml_light_types.dtd_item =
	| DTDAttribute of string * string * dtd_attr_type * dtd_attr_default
	| DTDElement of string * dtd_element_type

type dtd_result =
	| DTDNext
	| DTDNotMatched
	| DTDMatched
	| DTDMatchedResult of dtd_child

type error_pos = Xml_light_errors.error_pos = {
	eline : int;
	eline_start : int;
	emin : int;
	emax : int;
}

type parse_error = parse_error_msg * error_pos

exception Parse_error = Xml_light_errors.Dtd_parse_error
exception Check_error = Xml_light_errors.Dtd_check_error
exception Prove_error = Xml_light_errors.Dtd_prove_error

type dtd = dtd_item list

module StringMap = Map.Make(String)

type checked = Xml_light_dtd_check.checked

type dtd_state = {
	elements : dtd_element_type mut_map;
	attribs : (dtd_attr_type * dtd_attr_default) mut_map mut_map;
	mutable current : dtd_element_type;
	mutable curtag : string;
	state : (string * dtd_element_type) Stack.t;
}

let convert = function
	| Xml_lexer.EInvalidDTDDecl -> InvalidDTDDecl
	| Xml_lexer.EInvalidDTDElement -> InvalidDTDElement
	| Xml_lexer.EInvalidDTDTag -> InvalidDTDTag
	| Xml_lexer.EDTDItemExpected -> DTDItemExpected
	| Xml_lexer.EInvalidDTDAttribute -> InvalidDTDAttribute

let parse source : dtd =
	try
		Xml_lexer.init source;
		let dtd = Xml_lexer.dtd source in
		Xml_lexer.close source;
		dtd
	with
		| Xml_lexer.DTDError e ->
			Xml_lexer.close source;
			let pos = Xml_lexer.error_pos source in
			raise (Parse_error (convert e, pos))

let parse_string s = parse (Lexing.from_string s)
let parse_in ch = parse (Lexing.from_channel ch)

let parse_file fname =
	let ch =
		try open_in fname with Sys_error _ ->
			raise (Xml_light_errors.File_not_found fname)
	in
	try
		let x = parse (Lexing.from_channel ch) in
		close_in ch;
		x
	with
		e ->
			close_in ch;
			raise e

let check = Xml_light_dtd_check.check

let start_prove dtd root =
	let d = {
		elements = ref dtd.Xml_light_dtd_check.c_elements;
		attribs = ref (StringMap.map ref dtd.Xml_light_dtd_check.c_attribs);
		state = Stack.create();
		current = DTDChild (DTDTag root);
		curtag = "_root";
	} in
	try
		ignore(find_map d.elements (String.uppercase root));
		d
	with
		Not_found -> raise (Check_error (ElementNotDeclared root))


(* - for debug only - *)

let to_string_ref = ref (fun _ -> assert false)

let trace dtd tag =
	let item = DTDElement ("current",dtd.current) in
	printf "%s : %s\n"
		(match tag with None -> "#PCDATA" | Some t -> t)
		(!to_string_ref item)

exception TmpResult of dtd_result

let prove_child dtd tag =
	match dtd.current with
	| DTDEmpty -> raise (Prove_error EmptyExpected)
	| DTDAny -> ()
	| DTDChild elt ->
		let rec update = function
		| DTDTag s ->
			(match tag with
			| None -> DTDNotMatched
			| Some t when t = String.uppercase s -> DTDMatched
			| Some _ -> DTDNotMatched)
		| DTDPCData ->
			(match tag with
			| None -> DTDMatched
			| Some _ -> DTDNotMatched)
		| DTDOptional x ->
			(match update x with
			| DTDNotMatched
			| DTDNext -> DTDNext
			| DTDMatched
			| DTDMatchedResult _ -> DTDMatched)
		| DTDZeroOrMore x ->
			(match update x with
			| DTDNotMatched
			| DTDNext -> DTDNext
			| DTDMatched
			| DTDMatchedResult _ -> DTDMatchedResult (DTDZeroOrMore x))
		| DTDOneOrMore x ->
			(match update x with
			| DTDNotMatched
			| DTDNext -> DTDNotMatched
			| DTDMatched
			| DTDMatchedResult _ -> DTDMatchedResult (DTDZeroOrMore x))
		| DTDChoice l ->
			(try
				(match List.exists (fun x ->
					match update x with
					| DTDMatched -> true
					| DTDMatchedResult _ as r -> raise (TmpResult r)
					| DTDNext | DTDNotMatched -> false) l with
				| true -> DTDMatched
				| false -> DTDNotMatched)
			with
				TmpResult r -> r)
		| DTDChildren [] -> assert false (* DTD is checked ! *)
		| DTDChildren (h :: t) ->
			(match update h with
			| DTDNext ->
				(match t with
				| [] -> DTDNotMatched
				| _ -> update (DTDChildren t))
			| DTDNotMatched -> DTDNotMatched
			| DTDMatchedResult r ->
				DTDMatchedResult (DTDChildren (r::t))
			| DTDMatched ->
				match t with
				| [] -> DTDMatched
				| _ -> DTDMatchedResult (DTDChildren t))
		in
		match update elt with
		| DTDNext | DTDNotMatched ->
			(match tag with
			| None -> raise (Prove_error UnexpectedPCData)
			| Some t -> raise (Prove_error (UnexpectedTag t)))
		| DTDMatched ->
			dtd.current <- DTDEmpty
		| DTDMatchedResult r ->
			dtd.current <- DTDChild r

let is_nmtoken_char = function
	| 'A'..'Z' | 'a'..'z' | '0'..'9' | '.' | '-' | '_' | ':' -> true
	| _ -> false

let prove_attrib dtd hid hidref attr aname (atype,adef) accu =
	let aval = (try Some (List.assoc aname attr) with Not_found -> None) in
	(match atype, aval with
	| DTDCData, _ -> ()
	| DTDNMToken, None -> ()
	| DTDNMToken, Some v ->
		for i = 0 to String.length v - 1 do
			if not (is_nmtoken_char v.[i]) then raise (Prove_error (InvalidAttributeValue aname));
		done
	| DTDEnum l, None -> ()
	| DTDEnum l, Some v ->
		if not (List.exists ((=) v) l) then raise (Prove_error (InvalidAttributeValue aname))
	| DTDID, None -> ()
	| DTDID, Some id ->
		if mem_map hid id then raise (Prove_error (DuplicateID id));
		set_map hid id ()
	| DTDIDRef, None -> ()
	| DTDIDRef, Some idref ->
		set_map hidref idref ());
	match adef, aval with
	| DTDRequired, None -> raise (Prove_error (RequiredAttribute aname))
	| DTDFixed v, Some av when v <> av -> raise (Prove_error (InvalidAttributeValue aname))
	| DTDImplied, None -> accu
	| DTDFixed v , None
	| DTDDefault _, Some v
	| DTDDefault v, None
	| DTDRequired,  Some v
	| DTDImplied, Some v
	| DTDFixed _, Some v -> (aname,v) :: accu

let check_attrib ahash (aname,_) =
	try
		ignore(find_map ahash aname);
	with
		Not_found -> raise (Prove_error (UnexpectedAttribute aname))

let rec do_prove hid hidref dtd = function
	| PCData s ->
		prove_child dtd None;
		PCData s
	| Element (tag,attr,childs) ->
		let utag = String.uppercase tag in
		let uattr = List.map (fun (aname,aval) -> String.uppercase aname , aval) attr in
		prove_child dtd (Some utag);
		Stack.push (dtd.curtag,dtd.current) dtd.state;
		let elt = (try find_map dtd.elements utag with Not_found -> raise (Prove_error (UnexpectedTag tag))) in
		let ahash = (try find_map dtd.attribs utag with Not_found -> empty_map ()) in
		dtd.curtag <- tag;
		dtd.current <- elt;
		List.iter (check_attrib ahash) uattr;
		let attr = fold_map (prove_attrib dtd hid hidref uattr) ahash [] in
		let childs = ref (List.map (do_prove hid hidref dtd) childs) in
		(match dtd.current with
		| DTDAny
		| DTDEmpty -> ()
		| DTDChild elt ->
			let name = ref "" in
			let rec check = function
				| DTDTag t ->
					name := t;
					false
				| DTDPCData when !childs = [] ->
					childs := [PCData ""];
					true
				| DTDPCData ->
					name := "#PCDATA";
					false
				| DTDOptional _ -> true
				| DTDZeroOrMore _ -> true
				| DTDOneOrMore e ->
					ignore(check e);
					false
				| DTDChoice l -> List.exists check l
				| DTDChildren l -> List.for_all check l
			in
			match check elt with
			| true -> ()
			| false -> raise (Prove_error (ChildExpected !name)));
		let ctag, cur = Stack.pop dtd.state in
		dtd.curtag <- tag;
		dtd.current <- cur;
		Element (tag,attr,!childs)

let prove dtd root xml =
	let hid = create_map() in
	let hidref = create_map() in
	let x = do_prove hid hidref (start_prove dtd root) xml in
	iter_map (fun id () ->
		if not (mem_map hid id) then raise (Prove_error (MissingID id))
	) hidref;
	x

let parse_error_msg = function
	| InvalidDTDDecl -> "Invalid DOCTYPE declaration"
	| InvalidDTDElement -> "Invalid DTD element declaration"
	| InvalidDTDAttribute -> "Invalid DTD attribute declaration"
	| InvalidDTDTag -> "Invalid DTD tag"
	| DTDItemExpected -> "DTD item expected"

let parse_error (msg,pos) =
	if pos.emin = pos.emax then
		sprintf "%s line %d character %d" (parse_error_msg msg) pos.eline (pos.emin - pos.eline_start)
	else
		sprintf "%s line %d characters %d-%d" (parse_error_msg msg) pos.eline (pos.emin - pos.eline_start) (pos.emax - pos.eline_start)

let check_error = function
	| ElementDefinedTwice tag -> sprintf "Element '%s' defined twice" tag
	| AttributeDefinedTwice (tag,aname) -> sprintf "Attribute '%s' of element '%s' defined twice" aname tag
	| ElementEmptyContructor tag -> sprintf "Element '%s' has empty constructor" tag
	| ElementReferenced (tag,from) -> sprintf "Element '%s' referenced by '%s' is not declared" tag from
	| ElementNotDeclared tag -> sprintf "Element '%s' needed but is not declared" tag
	| WrongImplicitValueForID (tag,idname) -> sprintf "Attribute '%s' of type ID of element '%s' not defined with implicit value #REQUIRED or #IMPLIED" idname tag

let prove_error = function
	| UnexpectedPCData -> "Unexpected PCData"
	| UnexpectedTag tag -> sprintf "Unexpected tag : '%s'" tag
	| UnexpectedAttribute att -> sprintf "Unexpected attribute : '%s'" att
	| InvalidAttributeValue att -> sprintf "Invalid attribute value for '%s'" att
	| RequiredAttribute att -> sprintf "Required attribute not found : '%s'" att
	| ChildExpected cname -> sprintf "Child expected : '%s'" cname
	| EmptyExpected -> "No more children expected"
	| DuplicateID id  -> sprintf "ID '%s' used several times" id
	| MissingID idref -> sprintf "missing ID value for IDREF '%s'" idref

let to_string = function
	| DTDAttribute (tag,aname,atype,adef) ->
		let atype_to_string = function
			| DTDCData -> "CDATA"
			| DTDNMToken -> "NMTOKEN"
			| DTDEnum l -> sprintf "(%s)" (String.concat "|" l)
			| DTDID -> "ID"
			| DTDIDRef -> "IDREF"
		in
		let adefault_to_string = function
			| DTDDefault s -> sprintf "\"%s\"" s
			| DTDRequired -> "#REQUIRED"
			| DTDImplied -> "#IMPLIED"
			| DTDFixed s -> sprintf "#FIXED \"%s\"" s
		in
		sprintf "<!ATTLIST %s %s %s %s>" tag aname (atype_to_string atype) (adefault_to_string adef)
	| DTDElement (tag,etype) ->
		let rec echild_to_string = function
			| DTDTag s -> s
			| DTDPCData -> "#PCDATA"
			| DTDOptional c -> sprintf "%s?" (echild_to_string c)
			| DTDZeroOrMore c -> sprintf "%s*" (echild_to_string c)
			| DTDOneOrMore c -> sprintf "%s+" (echild_to_string c)
			| DTDChoice [c] -> echild_to_string c
			| DTDChoice l -> sprintf "(%s)" (String.concat "|" (List.map echild_to_string l))
			| DTDChildren [c] -> echild_to_string c
			| DTDChildren l -> sprintf "(%s)" (String.concat "," (List.map echild_to_string l))
		in
		let etype_to_string = function
			| DTDEmpty -> "EMPTY"
			| DTDAny -> "ANY"
			| DTDChild x ->
				let rec op_to_string = function
					| DTDOptional c -> sprintf "%s?" (op_to_string c)
					| DTDZeroOrMore c -> sprintf "%s*" (op_to_string c)
					| DTDOneOrMore c -> sprintf "%s+" (op_to_string c)
					| _ -> ""
				in
				let rec root = function
					| DTDOptional c
					| DTDZeroOrMore c
					| DTDOneOrMore c ->
						root c
					| DTDChoice [_]
					| DTDChildren [_] as x ->
						x, false
					| DTDChoice _
					| DTDChildren _ as x ->
						x, true
					| x -> x, false
				in
				match root x with
				| r, true -> sprintf "%s%s" (echild_to_string r) (op_to_string x)
				| r, false -> sprintf "(%s%s)" (echild_to_string r) (op_to_string x)
		in
		sprintf "<!ELEMENT %s %s>" tag (etype_to_string etype)

;;
to_string_ref := to_string
