(*
 * Copyright (C) 2006-2007 XenSource Ltd.
 * Copyright (C) 2008      Citrix Ltd.
 * Author Vincent Hanquez <vincent.hanquez@eu.citrix.com>
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

exception End_of_file


type watch = {
	con: t;
	token: string;
	path: string;
	base: string;
	is_relative: bool;
}

and t = {
(* 	xb: Xenbus.Xb.t; *)
	domid: int;
	domstr: string;
	transactions: (int32, Transaction.t) Hashtbl.t;
	mutable next_tid: int32;
	watches: (string, watch list) Hashtbl.t;
	mutable nb_watches: int;
	mutable stat_nb_ops: int;
	mutable perm: Perms.t;
}

let domains : (int, t) Hashtbl.t = Hashtbl.create 128

let watch_create ~con ~path ~token = { 
	con = con; 
	token = token; 
	path = path; 
	base = Store.Path.getdomainpath con.domid;
	is_relative = path.[0] <> '/' && path.[0] <> '@'
}

let get_con w = w.con
 
let number_of_transactions con =
	Hashtbl.length con.transactions

let anon_id_next = ref 1

let create (* xbcon *) dom =
	let con = 
	{
		domid = dom;
		domstr = "D" ^ (string_of_int dom); (* XXX unix domain socket *)
		transactions = Hashtbl.create 5;
		next_tid = 1l;
		watches = Hashtbl.create 8;
		nb_watches = 0;
		stat_nb_ops = 0;
		perm = Perms.of_domain dom;
	}
	in 
	Logging.new_connection ~tid:Transaction.none ~con:con.domstr;
	Hashtbl.replace domains dom con;
	con

(*
let get_fd con = Xenbus.Xb.get_fd con.xb
*)
let close con =
	Logging.end_connection ~tid:Transaction.none ~con:con.domstr;
	Hashtbl.remove domains con.domid;
	()
(*
	Xenbus.Xb.close con.xb
*)

let restrict con domid =
	con.perm <- Perms.restrict con.perm domid

(*
let send_reply con tid rid ty data =
	Xenbus.Xb.queue con.xb (Xenbus.Xb.Packet.create tid rid ty data)

let send_error con tid rid err = send_reply con tid rid Xs_packet.Op.Error (err ^ "\000")
let send_ack con tid rid ty = send_reply con tid rid ty "OK\000"
*)

let get_watch_path con path =
	if path.[0] = '@' || path.[0] = '/' then
		path
	else
		let rpath = Store.Path.getdomainpath con.domid in
		rpath ^ path

let get_watches (con: t) path =
	if Hashtbl.mem con.watches path
	then Hashtbl.find con.watches path
	else []

(** True if string 'x' starts with prefix 'prefix' *)
let startswith prefix x =
        let x_l = String.length x and prefix_l = String.length prefix in
        prefix_l <= x_l && String.sub x 0 prefix_l  = prefix

let get_children_watches con path =
	let path = path ^ "/" in
	List.concat (Hashtbl.fold (fun p w l ->
		if startswith path p then w :: l else l) con.watches [])

(*
let is_dom0 con =
	Perms.Connection.is_dom0 (get_perm con)
*)

let add_watch con path token =
(*
	if !Quota.activate && !Define.maxwatch > 0 &&
	   not (is_dom0 con) && con.nb_watches > !Define.maxwatch then
		raise Quota.Limit_reached;
*)
	let apath = get_watch_path con path in
	let l = get_watches con apath in
	if List.exists (fun w -> w.token = token) l then
		raise Store.Path.Already_exist;
	let watch = watch_create ~con ~token ~path in
	Hashtbl.replace con.watches apath (watch :: l);
	con.nb_watches <- con.nb_watches + 1;
	apath, watch

let del_watch con path token =
	let apath = get_watch_path con path in
	let ws = Hashtbl.find con.watches apath in
	let w = List.find (fun w -> w.token = token) ws in
	let filtered = List.filter (fun e -> e != w) ws in
	if List.length filtered > 0 then
		Hashtbl.replace con.watches apath filtered
	else
		Hashtbl.remove con.watches apath;
	con.nb_watches <- con.nb_watches - 1;
	apath, w

let list_watches con =
	let ll = Hashtbl.fold 
		(fun _ watches acc -> List.map (fun watch -> watch.path, watch.token) watches :: acc)
		con.watches [] in
	List.concat ll

(*
let fire_single_watch watch =
	let data = Utils.join_by_null [watch.path; watch.token; ""] in
	send_reply watch.con Transaction.none 0 Xs_packet.Op.Watchevent data

let fire_watch watch path =
	let new_path =
		if watch.is_relative && path.[0] = '/'
		then begin
			let n = String.length watch.base
		 	and m = String.length path in
			String.sub path n (m - n)
		end else
			path
	in
	let data = Utils.join_by_null [ new_path; watch.token; "" ] in
	send_reply watch.con Transaction.none 0 Xs_packet.Op.Watchevent data
*)

let find_next_tid con =
	let ret = con.next_tid in con.next_tid <- Int32.add con.next_tid 1l; ret

let start_transaction con store =
(*
	if !Define.maxtransaction > 0 && not (is_dom0 con)
	&& Hashtbl.length con.transactions > !Define.maxtransaction then
		raise Quota.Transaction_opened;
*)
	let id = find_next_tid con in
	let ntrans = Transaction.make id store in
	Hashtbl.add con.transactions id ntrans;
	Logging.start_transaction ~tid:id ~con:con.domstr;
	id

let unregister_transaction con tid =
	Hashtbl.remove con.transactions tid

let get_transaction con tid =
	Hashtbl.find con.transactions tid

(*
let do_input con = Xenbus.Xb.input con.xb
let has_input con = Xenbus.Xb.has_in_packet con.xb
let pop_in con = Xenbus.Xb.get_in_packet con.xb
let has_more_input con = Xenbus.Xb.has_more_input con.xb

let has_output con = Xenbus.Xb.has_output con.xb
let has_new_output con = Xenbus.Xb.has_new_output con.xb
let peek_output con = Xenbus.Xb.peek_output con.xb
let do_output con = Xenbus.Xb.output con.xb
*)

let incr_ops con = con.stat_nb_ops <- con.stat_nb_ops + 1

let mark_symbols con =
	Hashtbl.iter (fun _ t -> Store.mark_symbols (Transaction.get_store t)) con.transactions

let stats con =
	Hashtbl.length con.watches, con.stat_nb_ops

(*
let hexify s =
        let hexseq_of_char c = sprintf "%02x" (Char.code c) in
        let hs = String.create (String.length s * 2) in
        for i = 0 to String.length s - 1
        do
                let seq = hexseq_of_char s.[i] in
                hs.[i * 2] <- seq.[0];
                hs.[i * 2 + 1] <- seq.[1];
        done;
        hs

let dump con chan =
	match con.dom with
	| Some dom -> 
		let domid = Domain.get_id dom in
		(* dump domain *)
		Domain.dump dom chan;
		(* dump watches *)
		List.iter (fun (path, token) ->
			Printf.fprintf chan "watch,%d,%s,%s\n" domid (hexify path) (hexify token)
			) (list_watches con);
	| None -> ()
*)

let debug con =
	let watches = List.map (fun (path, token) -> Printf.sprintf "watch %s: %s %s\n" con.domstr path token) (list_watches con) in
	String.concat "" watches
