open Xml_light_types
open Xml_light_errors
open Xml_light_utils

type checked = {
	c_elements : dtd_element_type map;
	c_attribs : (dtd_attr_type * dtd_attr_default) map map;
}

let check dtd =
	let attribs = create_map() in
	let hdone = create_map() in
	let htodo = create_map() in
	let ftodo tag from =
		try
			ignore(find_map hdone tag);
		with
			Not_found ->
				try
					match find_map htodo tag with
					| None -> set_map htodo tag from
					| Some _ -> ()
				with
					Not_found ->
						set_map htodo tag from
	in
	let fdone tag edata =
		try
			ignore(find_map hdone tag);
			raise (Dtd_check_error (ElementDefinedTwice tag));
		with
			Not_found ->
				unset_map htodo tag;
				set_map hdone tag edata
	in
	let fattrib tag aname adata =
		(match adata with
	    | DTDID,DTDImplied -> ()
	    | DTDID,DTDRequired -> ()
	    | DTDID,_ -> raise (Dtd_check_error (WrongImplicitValueForID (tag,aname)))
	    | _ -> ());
		let h = (try
				find_map attribs tag
			with
				Not_found ->
					let h = create_map() in
					set_map attribs tag h;
					h) in
		try
			ignore(find_map h aname);
			raise (Dtd_check_error (AttributeDefinedTwice (tag,aname)));
		with
			Not_found ->
				set_map h aname adata
	in
	let check_item = function
		| DTDAttribute (tag,aname,atype,adef) ->
			let utag = String.uppercase tag in
			ftodo utag None;
			fattrib utag (String.uppercase aname) (atype,adef)
		| DTDElement (tag,etype) ->
			let utag = String.uppercase tag in
			fdone utag etype;
			let check_type = function
				| DTDEmpty -> ()
				| DTDAny -> ()
				| DTDChild x ->
					let rec check_child = function
						| DTDTag s -> ftodo (String.uppercase s) (Some utag)
						| DTDPCData -> ()
						| DTDOptional c
						| DTDZeroOrMore c
						| DTDOneOrMore c ->
							check_child c
						| DTDChoice []
						| DTDChildren [] ->
							raise (Dtd_check_error (ElementEmptyContructor tag))
						| DTDChoice l
						| DTDChildren l ->
							List.iter check_child l
					in
					check_child x
			in
			check_type etype
	in
	List.iter check_item dtd;
	iter_map (fun t from ->
		match from with
		| None -> raise (Dtd_check_error (ElementNotDeclared t))
		| Some tag -> raise (Dtd_check_error (ElementReferenced (t,tag)))
	) htodo;
	{
		c_elements = !hdone;
		c_attribs = StringMap.map (!) !attribs;
	}
