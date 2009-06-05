% Nitrogen Web Framework for Erlang
% Copyright (c) 2008-2009 Rusty Klophaus
% See MIT-LICENSE for licensing information.

-module (wf_continuation).
-include ("wf.inc").
-export ([
	continue/3, 
	continue/4, 
	continue/5, 
	register/3, 
	wait/1, 
	get_result/1
]).

continue(Tag, Function, Context) ->
	continue(Tag, Function, 100, Context).
	
continue(Tag, Function, Interval, Context) ->
	continue(Tag, Function, Interval, 20000, Context).

continue(Tag, Function, Interval, Timeout, Context) ->
	Pid = spawn(fun() -> start_continuation_wrapper(Tag, Function, Interval, Timeout) end),
	{ok, Context1} = ?MODULE:register(Pid, Interval, Context),
	{ok, Pid, Context1}.
	
register(Pid, Interval, Context) ->
	{ok, Context1} = wff:wire(#event { type=continuation, delay=Interval, postback=Pid }, Context),
	{ok, Context1}.

get_result(Pid) ->
	case wf_utils:is_process_alive(Pid) of
		true -> 
			Pid!{get_result, self()},
			Result = receive M -> M end,
			Result;
		false ->
			undefined
	end.	

wait([]) -> ok;
wait([H|T]) -> 
	receive after 100 -> ok end,
	case wf_utils:is_process_alive(H) of
		true -> wait([H|T]);
		false -> wait(T)
	end;
wait(Pid) -> wait([Pid]).

%%% PRIVATE FUNCTIONS %%%
			
start_continuation_wrapper(Tag, Function, Interval, Timeout) ->
	WrapperPid = self(),
	Pid = spawn(fun() -> 
		Result = try Function() catch Type : Message -> {error, Type, Message} end,
		WrapperPid!{result, self(), Result} 
	end),
	erlang:send_after(Timeout, self(), timeout),
	continuation_wrapper(Tag, Pid, Interval, no_result).

continuation_wrapper(Tag, Pid, Interval, Result) ->
	receive 
		{result, Pid, NewResult} -> 
			continuation_wrapper(Tag, Pid, Interval, NewResult);
			
		{get_result, CallingPid} when Result == no_result ->
			CallingPid!{running, Interval},
			continuation_wrapper(Tag, Pid, Interval + 100, Result);
			
		{get_result, CallingPid} -> 
			CallingPid!{done, Tag, Result};
		
		timeout ->
			continuation_wrapper(Tag, Pid, Interval, timeout)
			
		after 5 * 60 * 1000 -> stop_running
	end.