defmodule Teiserver.Agents.BattlehostAgentServer do
  use GenServer
  alias Teiserver.Agents.AgentLib
  alias Teiserver.Battle
  require Logger

  @tick_period 5000
  @inaction_chance 0.5
  @leave_chance 0.5

  def handle_info(:startup, state) do
    socket = AgentLib.get_socket()
    AgentLib.login(socket, %{
      name: "BattlehostAgentServer_#{state.name}",
      email: "BattlehostAgentServer_#{state.name}@agent_email",
      extra_data: %{}
    })

    :timer.send_interval(@tick_period, self(), :tick)

    {:noreply, %{state | socket: socket}}
  end

  def handle_info(:tick, state) do
    battle = Battle.get_battle(state.battle_id)

    new_state = cond do
      # Chance of doing nothing
      :rand.uniform() <= state.inaction_chance ->
        state

      battle == nil ->
        Logger.warn("#{state.name} - opening")
        open_battle(state)
        state

      state.always_leave ->
        Logger.warn("#{state.name} - leaving anyway")
        leave_battle(state)

      battle.player_count == 0 and battle.spectator_count == 0 ->
        if :rand.uniform() <= @leave_chance do
          Logger.warn("#{state.name} - leaving empty")
          leave_battle(state)
        else
          state
        end

      # There are players in a battle, we do nothing
      true ->
        state
    end

    {:noreply, new_state}
  end

  def handle_info({:ssl, _socket, data}, state) do
    new_state = data
    |> AgentLib.translate
    |> Enum.reduce(state, fn data, acc ->
      handle_msg(data, acc)
    end)

    {:noreply, new_state}
  end

  defp handle_msg(nil, state), do: state
  defp handle_msg(%{"cmd" => "s.battle.request_to_join", "userid" => userid}, state) do
    cmd = %{cmd: "c.battle.respond_to_join_request", userid: userid, response: "approve"}
    AgentLib._send(state.socket, cmd)
    state
  end
  defp handle_msg(%{"cmd" => "s.battle.leave", "result" => "success"}, state) do
    %{state | battle_id: nil}
  end
  defp handle_msg(%{"cmd" => "s.battle.create", "battle" => %{"id" => battle_id}}, state) do
    %{state | battle_id: battle_id}
  end

  defp open_battle(state) do
    cmd = %{
      cmd: "c.battle.create",
      battle: %{
        cmd: "c.battles.create",
        name: "BH #{state.name} - #{:rand.uniform(9999)}",
        nattype: "none",
        password: "password2",
        port: 1234,
        game_hash: "string_of_characters",
        map_hash: "string_of_characters",
        map_name: "koom valley",
        game_name: "BAR",
        engine_name: "spring-105",
        engine_version: "105.1.2.3",
        settings: %{
          max_players: 12
        }
      }
    }
    AgentLib._send(state.socket, cmd)
  end

  defp leave_battle(state) do
    AgentLib._send(state.socket, %{cmd: "c.battle.leave"})
    AgentLib.post_agent_update(state.id, "left battle")
    %{state | battle_id: nil}
  end

  # Startup
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts[:data], opts)
  end

  def init(opts) do
    send(self(), :startup)

    {:ok,
     %{
       id: opts.id,
       number: opts.number,
       name: Map.get(opts, :name, opts.number),
       battle_id: nil,
       socket: nil,
       leave_chance: Map.get(opts, :leave_chance, @leave_chance),
       inaction_chance: Map.get(opts, :leave_chance, @inaction_chance),
       always_leave: Map.get(opts, :always_leave, false)
     }}
  end
end
