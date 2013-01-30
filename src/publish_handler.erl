%% Feel free to use, reuse and abuse the code in this file.

-module(publish_handler).
-behaviour(cowboy_http_handler).
-export([init/3, handle/2, terminate/2, intersect/2, get_ids/1]).

init({_Any, http}, Req, []) ->
	{ok, Req, undefined}.

handle(Req, State) ->

	case cowboy_http_req:method(Req) of 
		{'POST', Req} ->
			{Qs, _} = cowboy_http_req:body_qs(Req),
			%{_, Time} = lists:keyfind(<<"time">>, 1, Qs),
			{_, Text} = lists:keyfind(<<"text">>, 1, Qs),
			{_, Author} = lists:keyfind(<<"author">>, 1, Qs),

			%{PeerAddr, _} = cowboy_http_req:peer_addr(Req),
			{{Y,Mo,D},{H,M,S}} = erlang:localtime(),
			Time = list_to_binary(io_lib:format("~B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [Y,Mo,D,H,M,S])),
			% cheap Id
			Id = ets:info(posts, size) + 1,
			ets:insert(posts, {Id, Author, Time, Text}),

			%% route the data to the pubsub broker
			tagit_listener ! {Id, Author, Time, Text},

			{ok, Req2} = cowboy_http_req:reply(200, [], Req);

		{_, Req} ->
			{Path2, _} = cowboy_http_req:qs_val(<<"path">>, Req),
			{ok, [H|Path]} = json:decode(Path2), %todo handle empty path
			io:format("o20 ~p ~n", [[H|Path]]),

			Ids = from_path(Path, get_ids(H)),
			io:format("o20 ~p ~n", [Ids]),
			Res = [ tuple_to_list(hd(ets:lookup(posts, Id)))++[lists:flatten(ets:match(posts_tags, {Id,'$1'}))] || Id <- Ids],
			{ok, Resj} = json:encode(Res),
			io:format("o20 ~p ~n", [Resj]),
			{ok, Req2} = cowboy_http_req:reply(200, [{'Content-Type', <<"application/json">>}], Resj, Req)		
	end,
	{ok, Req2, State}.


terminate(_Req, _State) ->
	ok.


from_path([], Ids) -> Ids;
from_path(_, []) -> []; %no need to continue
from_path([Tagstr|Rest], Ids) ->
	Ids2 = get_ids(Tagstr),
	io:format("o0 ~p ~p ~n", [Ids2,Ids]),
	from_path(Rest, intersect(Ids2, Ids)).

get_ids(Tagstr) ->
	Tags = string:tokens(binary_to_list(Tagstr), " " ),
	Ids2 = lists:sort(proplists:get_keys(lists:flatmap(fun(Tag)-> ets:match_object(posts_tags, {'$1',list_to_binary(Tag)}) end, Tags))).


intersect([], _) -> [];
intersect(_, []) -> [];
intersect([H1|T1], [H2|T2]) ->
	if 
		H1<H2 ->
			intersect(T1,[H2|T2]);
		H1>H2 ->
			intersect([H1|T1],T2);
		true ->
			[H1] ++ intersect(T1,T2)
	end.

