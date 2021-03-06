%% Feel free to use, reuse and abuse the code in this file.

-module(publish_handler).

-export([init/3, handle/2, terminate/3]).

-include_lib("stdlib/include/ms_transform.hrl").

init(_Transport, Req, []) ->
	{ok, Req, undefined}.

handle(Req, State) ->
	
	case cowboy_req:method(Req) of 
		{<<"POST">>, Req} ->
			{ok, Qs, _} = cowboy_req:body_qs(Req),
			Author = proplists:get_value(<<"author">>, Qs),
			Text = proplists:get_value(<<"text">>, Qs),
			%{_, Time} = lists:keyfind(<<"time">>, 1, Qs),

			%{PeerAddr, _} = cowboy_req:peer_addr(Req),
			{{Y,Mo,D},{H,M,S}} = erlang:localtime(),
			Time = list_to_binary(io_lib:format("~B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [Y,Mo,D,H,M,S])),
			% cheap Id
			Id = ets:info(posts, size) + 1,
			ets:insert(posts, {Id, Author, Time, Text}),
			dets:insert(dposts, {Id, Author, Time, Text}),

			%% route the data to the pubsub broker
			tagit_listener ! {Id, Author, Time, Text}, % or tagit_listener:process({Id, Author, Time, Text}),

			{ok, Req2} = cowboy_req:reply(200, [], Req);

		{_, Req} ->
			{Path, _} = cowboy_req:qs_val(<<"path">>, Req, <<>>),
			% todo: real pagination with limit / offset
			if
				Path == <<>> ->
					{Limit2, _} = cowboy_req:qs_val(<<"limit">>, Req, <<"10">>),
					Size = ets:info(posts, size), Limit = list_to_integer(binary_to_list(Limit2)), 
					io:format("o20 ~p ~p ~n", [Size, Limit ]),
					Posts = ets:select(posts, ets:fun2ms(fun({Id,A,T,C}) when Id > Size-Limit -> [Id,A,T,C] end)),
					Res = [ [Id,A,T,C]++[lists:flatten(ets:match(posts_tags, {Id,'$1'}))] || [Id,A,T,C] <- Posts];
				true ->		
					[H|Rest] = re:split(Path, "&", [{return,binary}]),
					io:format("o20 ~p ~n", [[H|Rest]]),

					Ids = from_path(Rest, get_ids(H)),
					Res = [ tuple_to_list(hd(ets:lookup(posts, Id)))++[lists:flatten(ets:match(posts_tags, {Id,'$1'}))] || Id <- Ids]
			end,
			{ok, Resj} = json:encode(Res),
			{ok, Req2} = cowboy_req:reply(200, [{<<"content-type">>, <<"application/json">>}], Resj, Req)		
	end,
	{ok, Req2, State}.


terminate(_Reason, _Req, _State) ->
	ok.

%% util function that recurse get_ids and intersect along the path of tags (tags separated with &)
from_path([], Ids) -> Ids;
from_path(_, []) -> []; %no need to continue
from_path([Tagstr|Rest], Ids) ->
	Ids2 = get_ids(Tagstr),
	from_path(Rest, intersect(Ids2, Ids)).

%% util function to get posts ids with certain tags
get_ids(Tagstr) ->
	Tags = re:split(Tagstr, " |\\+", [{return,binary}]),
	lists:sort(proplists:get_keys(lists:flatmap(fun(Tag)-> ets:match_object(posts_tags, {'$1',Tag}) end, Tags))).


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

