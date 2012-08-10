(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open OUnit

let ( |> ) a b = b a
let id x = x

let unbox = function
	| None -> failwith "unbox"
	| Some x -> x

let op_ids _ =
  let open Xs_packet.Op in
  for i = 0 to 100 do (* higher than the highest ID *)
    let i' = Int32.of_int i in
    match of_int32 i' with
      | None -> ()
      | Some x -> assert (to_int32 x = i')
  done

let example_acl =
	let open Xs_packet.ACL in
    { owner = 5; other = READ; acl = [ 2, WRITE; 3, RDWR ] }

let acl_parser _ =
  let open Xs_packet.ACL in
  let ts = [
    { owner = 5; other = READ; acl = [ 2, WRITE; 3, RDWR ] };
    { owner = 1; other = WRITE; acl = [] };
  ] in
  let ss = List.map to_string ts in
  let ts' = List.map of_string ss in
  let printer = function
    | None -> "None"
    | Some x -> "Some " ^ to_string x in
  List.iter
    (fun (x, y) -> assert_equal ~msg:"acl" ~printer x y)
    (List.combine (List.map (fun x -> Some x) ts) ts')

let test_packet_parser choose pkt () =
    let open Xs_packet in
    let p = ref (Parser.start ()) in
    let s = to_string pkt in
    let i = ref 0 in
    let finished = ref false in
    while not !finished do
      match Parser.state !p with
	| Parser.Need_more_data x ->
	  let n = choose x in
	  p := Parser.input !p (String.sub s !i n);
	  i := !i + n
	| Parser.Packet pkt' ->
	  assert(get_tid pkt = (get_tid pkt'));
	  assert(get_ty pkt = (get_ty pkt'));
	  assert(get_data pkt = (get_data pkt'));
	  assert(get_rid pkt = (get_rid pkt'));
	  finished := true
	| _ ->
	  failwith (Printf.sprintf "parser failed for %s" (pkt |> get_ty |> Op.to_string))
    done


open Lwt


let test _ =
  let t = return () in
  Lwt_main.run t

type example_packet = {
	op: Xs_packet.Op.t;
	packet: Xs_packet.t;
	wire_fmt: string;
}
let make_example_request op pkt_opt wire_fmt = match pkt_opt with
	| None -> failwith (Printf.sprintf "make_example_request:%s" (Xs_packet.Op.to_string op))
	| Some x -> {
		op = op;
		packet = x;
		wire_fmt = wire_fmt;
	}

let example_request_packets =
	let open Xs_packet.Request in
    let open Xs_packet.Op in [
		make_example_request Directory (directory "/whatever/whenever" 5l)
			"\x01\x00\x00\x00\x0f\x00\x00\x00\x05\x00\x00\x00\x13\x00\x00\x00\x2f\x77\x68\x61\x74\x65\x76\x65\x72\x2f\x77\x68\x65\x6e\x65\x76\x65\x72\x00";
		make_example_request Read (read "/a/b/c" 6l)
			"\x02\x00\x00\x00\x0e\x00\x00\x00\x06\x00\x00\x00\x07\x00\x00\x00\x2f\x61\x2f\x62\x2f\x63\x00";
		make_example_request Getperms (getperms "/a/b" 7l)
			"\x03\x00\x00\x00\x0d\x00\x00\x00\x07\x00\x00\x00\x05\x00\x00\x00\x2f\x61\x2f\x62\x00";
		make_example_request Rm (rm "/" 0l)
			"\x0d\x00\x00\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x2f\x00";
		make_example_request Setperms (setperms "/" example_acl 1l)
			"\x0e\x00\x00\x00\x0b\x00\x00\x00\x01\x00\x00\x00\x0b\x00\x00\x00\x2f\x00\x72\x35\x00\x77\x32\x00\x62\x33\x00";
		make_example_request Write (write "/key" "value" 1l)
			"\x0b\x00\x00\x00\x0a\x00\x00\x00\x01\x00\x00\x00\x0a\x00\x00\x00\x2f\x6b\x65\x79\x00\x76\x61\x6c\x75\x65";
		make_example_request Mkdir (mkdir "/" 1024l)
			"\x0c\x00\x00\x00\x09\x00\x00\x00\x00\x04\x00\x00\x02\x00\x00\x00\x2f\x00";
		make_example_request Transaction_start (transaction_start ())
			"\x06\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00";
		make_example_request Transaction_end (transaction_end true 1l)
			"\x07\x00\x00\x00\x07\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x54\x00";
		make_example_request Introduce (introduce 4 5n 1)
			"\x08\x00\x00\x00\x06\x00\x00\x00\x00\x00\x00\x00\x06\x00\x00\x00\x34\x00\x35\x00\x31\x00";
		make_example_request Release (release 2)
			"\x09\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x32\x00";
		make_example_request Resume (resume 3)
			"\x12\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x33\x00";
		make_example_request Getdomainpath (getdomainpath 3)
			"\x0a\x00\x00\x00\x03\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x33\x00";
		make_example_request Watch (watch "/foo/bar" (Xs_packet.Token.of_user_string "something"))
			"\x04\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x15\x00\x00\x00\x2f\x66\x6f\x6f\x2f\x62\x61\x72\x00\x31\x3a\x73\x6f\x6d\x65\x74\x68\x69\x6e\x67\x00";
		make_example_request Unwatch (unwatch "/foo/bar" (Xs_packet.Token.of_user_string "somethinglse"))
			"\x05\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x18\x00\x00\x00\x2f\x66\x6f\x6f\x2f\x62\x61\x72\x00\x30\x3a\x73\x6f\x6d\x65\x74\x68\x69\x6e\x67\x6c\x73\x65\x00";
		make_example_request Debug (debug [ "a"; "b"; "something" ])
			"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0e\x00\x00\x00\x61\x00\x62\x00\x73\x6f\x6d\x65\x74\x68\x69\x6e\x67\x00"
	]

let make_example_response op f wire_fmt =
	let request = List.find (fun x -> x.op = op) example_request_packets in {
		op = op;
		packet = f request.packet;
		wire_fmt = wire_fmt;
	}

(* We use the example requests to generate example responses *)
let example_response_packets =
	let open Xs_packet in
	let open Xs_packet.Response in [
		make_example_response Op.Read (fun t -> read t "theresult")
			"\x02\x00\x00\x00\x0e\x00\x00\x00\x06\x00\x00\x00\x09\x00\x00\x00\x74\x68\x65\x72\x65\x73\x75\x6c\x74";
		make_example_response Op.Read (fun t -> read t "")
			"\x02\x00\x00\x00\x0e\x00\x00\x00\x06\x00\x00\x00\x00\x00\x00\x00";
		make_example_response Op.Getperms (fun t -> getperms t (Xs_packet.ACL.( { owner = 2; other = READ; acl = [ 4, NONE ] } )))
			"\x03\x00\x00\x00\x0d\x00\x00\x00\x07\x00\x00\x00\x06\x00\x00\x00\x72\x32\x00\x6e\x34\x00";
		make_example_response Op.Getdomainpath (fun t -> getdomainpath t "/local/domain/4")
			"\x0a\x00\x00\x00\x03\x00\x00\x00\x00\x00\x00\x00\x10\x00\x00\x00\x2f\x6c\x6f\x63\x61\x6c\x2f\x64\x6f\x6d\x61\x69\x6e\x2f\x34\x00";
		make_example_response Op.Transaction_start (fun t -> transaction_start t 3l)
			"\x06\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x33\x00";
		make_example_response Op.Directory (fun t -> directory t [ "a"; "b"; "c"; "aseasyas"; "1"; "2"; "3" ])
			"\x01\x00\x00\x00\x0f\x00\x00\x00\x05\x00\x00\x00\x15\x00\x00\x00\x61\x00\x62\x00\x63\x00\x61\x73\x65\x61\x73\x79\x61\x73\x00\x31\x00\x32\x00\x33\x00";
		make_example_response Op.Write write
			"\x0b\x00\x00\x00\x0a\x00\x00\x00\x01\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Mkdir mkdir
			"\x0c\x00\x00\x00\x09\x00\x00\x00\x00\x04\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Rm rm
			"\x0d\x00\x00\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Setperms setperms
			"\x0e\x00\x00\x00\x0b\x00\x00\x00\x01\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Watch watch
			"\x04\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Unwatch unwatch
			"\x05\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		make_example_response Op.Transaction_end transaction_end
			"\x07\x00\x00\x00\x07\x00\x00\x00\x01\x00\x00\x00\x03\x00\x00\x00\x4f\x4b\x00";
		{
			op = Op.Error;
			packet = error (Xs_packet.Request.directory "/foo" 2l |> unbox) "whatyoutalkingabout";
			wire_fmt =
				"\x10\x00\x00\x00\x10\x00\x00\x00\x02\x00\x00\x00\x14\x00\x00\x00\x77\x68\x61\x74\x79\x6f\x75\x74\x61\x6c\x6b\x69\x6e\x67\x61\x62\x6f\x75\x74\x00"
		}
	]

let example_packets = example_request_packets @ example_response_packets

let rec ints first last =
	if first > last then [] else first :: (ints (first + 1) last)

let hexstring x =
	String.concat "" ([
		"\"";
	] @ (
		List.map (fun i -> Printf.sprintf "\\x%02x" (int_of_char x.[i])) (ints 0 (String.length x - 1))
	) @ [
		"\"";
	])

(*
let error_unmarshal _ =
  let open Xs_packet.Response in
  let enoent = 
*)
let _ =
  let verbose = ref false in
  Arg.parse [
    "-verbose", Arg.Unit (fun _ -> verbose := true), "Run in verbose mode";
  ] (fun x -> Printf.fprintf stderr "Ignoring argument: %s" x)
    "Test xenstore protocol code";

  let packet_parsing choose =
    let f = test_packet_parser choose in
    "packet_parsing" >:::
		(List.map (fun example ->
			let description = Xs_packet.Op.to_string example.op in
			description >:: f example.packet
		) example_packets) in
  let packet_printing =
	  "packet_printing" >:::
		  (List.map (fun example ->
			  let description = Xs_packet.Op.to_string example.op in
			  description >:: (fun () -> assert_equal ~msg:description ~printer:hexstring (Xs_packet.to_string example.packet) example.wire_fmt)
		  ) example_packets) in
  let suite = "xenstore" >:::
    [
      "op_ids" >:: op_ids;
      "acl_parser" >:: acl_parser;
      packet_parsing id;
      packet_parsing (fun _ -> 1);
	  packet_printing;
      "test" >:: test;
    ] in
  run_test_tt ~verbose:!verbose suite
