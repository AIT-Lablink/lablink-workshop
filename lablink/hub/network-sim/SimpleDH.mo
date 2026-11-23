within ;
package SimpleDH "Simple district heating network with two substations, based on IDEAS"
  extends Modelica.Icons.Package;

  model SegmentedPipe
    "Plug flow pipe split into nSeg identical segments, with temperature and pressure sensors at every segment end"
    extends IDEAS.Fluid.Interfaces.PartialTwoPortInterface;

    parameter Integer nSeg(min=1) = 3 "Number of identical segments";
    parameter Modelica.Units.SI.Length length "Total pipe length";
    parameter Modelica.Units.SI.Length dh "Hydraulic (inner) diameter";
    parameter Modelica.Units.SI.Height roughness=2.5e-5 "Absolute roughness";
    parameter Real fac=1 "Factor for additional resistances (bends etc.)";
    parameter Modelica.Units.SI.Length dIns "Insulation thickness";
    parameter Modelica.Units.SI.ThermalConductivity kIns "Insulation conductivity";
    parameter Modelica.Units.SI.Length thickness=0.0035 "Pipe wall thickness";
    parameter Modelica.Units.SI.Temperature T_start=Medium.T_default
      "Initial fluid temperature in all segments and sensors"
      annotation (Dialog(tab="Initialization"));
    parameter Modelica.Units.SI.Time tauSen=0
      "Time constant of temperature sensors (0 = ideal, no sensor dynamics)"
      annotation (Dialog(tab="Advanced"));

    IDEAS.Fluid.FixedResistances.PlugFlowPipe pip[nSeg](
      redeclare each final package Medium = Medium,
      each final m_flow_nominal=m_flow_nominal,
      each final allowFlowReversal=allowFlowReversal,
      each final length=length/nSeg,
      each final dh=dh,
      each final roughness=roughness,
      each final fac=fac,
      each final dIns=dIns,
      each final kIns=kIns,
      each final thickness=thickness,
      each final T_start_in=T_start,
      each final T_start_out=T_start) "Pipe segments"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}})));

    IDEAS.Fluid.Sensors.TemperatureTwoPort senT[nSeg + 1](
      redeclare each final package Medium = Medium,
      each final m_flow_nominal=m_flow_nominal,
      each final allowFlowReversal=allowFlowReversal,
      each final tau=tauSen,
      each final T_start=T_start)
      "Temperature sensors at segment ends (index 1 = port_a, nSeg+1 = port_b)"
      annotation (Placement(transformation(extent={{-60,-10},{-40,10}})));

    IDEAS.Fluid.Sensors.Pressure senP[nSeg + 1](
      redeclare each final package Medium = Medium)
      "Pressure sensors at segment ends"
      annotation (Placement(transformation(extent={{-80,20},{-60,40}})));

    Modelica.Thermal.HeatTransfer.Interfaces.HeatPort_a heatPort
      "Surroundings (ground) of all segments"
      annotation (Placement(transformation(extent={{-10,90},{10,110}})));

    Modelica.Blocks.Interfaces.RealOutput T[nSeg + 1](
      each final unit="K", each displayUnit="degC")
      "Fluid temperature at segment ends"
      annotation (Placement(transformation(extent={{100,50},{120,70}})));
    Modelica.Blocks.Interfaces.RealOutput p[nSeg + 1](
      each final unit="Pa", each displayUnit="bar")
      "Absolute pressure at segment ends"
      annotation (Placement(transformation(extent={{100,20},{120,40}})));

    Modelica.Units.SI.HeatFlowRate QLos_flow = -heatPort.Q_flow
      "Total heat loss to surroundings (positive = loss)";

  equation
    connect(port_a, senT[1].port_a)
      annotation (Line(points={{-100,0},{-60,0}}, color={0,127,255}));
    for i in 1:nSeg loop
      connect(senT[i].port_b, pip[i].port_a)
        annotation (Line(points={{-40,0},{-10,0}}, color={0,127,255}));
      connect(pip[i].port_b, senT[i + 1].port_a)
        annotation (Line(points={{10,0},{20,0},{20,-30},{-74,-30},{-74,0},{-60,0}},
          color={0,127,255}, pattern=LinePattern.Dash));
      connect(pip[i].heatPort, heatPort)
        annotation (Line(points={{0,10},{0,100}}, color={191,0,0}));
    end for;
    connect(senT[nSeg + 1].port_b, port_b)
      annotation (Line(points={{-40,0},{-30,0},{-30,-50},{90,-50},{90,0},{100,0}},
        color={0,127,255}));

    for i in 1:nSeg + 1 loop
      connect(senP[i].port, senT[i].port_a)
        annotation (Line(points={{-70,20},{-70,0},{-60,0}}, color={0,127,255}));
    end for;

    connect(senT.T, T)
      annotation (Line(points={{-50,11},{-50,60},{110,60}}, color={0,0,127}));
    connect(senP.p, p)
      annotation (Line(points={{-59,30},{110,30}}, color={0,0,127}));

    annotation (
      Icon(graphics={
          Rectangle(extent={{-100,30},{100,-30}}, lineColor={0,0,0},
            fillColor={0,127,255}, fillPattern=FillPattern.HorizontalCylinder),
          Line(points={{-33,30},{-33,-30}}, thickness=0.5),
          Line(points={{33,30},{33,-30}}, thickness=0.5),
          Text(extent={{-100,80},{100,40}}, textString="nSeg=%nSeg")}),
      Diagram(graphics={
          Text(extent={{-90,-60},{90,-80}}, textColor={95,95,95},
            textString="Array chain: senT[i] -> pip[i] -> senT[i+1],  i = 1..nSeg  (dashed = link to next segment)")}),
      Documentation(info="<html>
<p>Chain of <code>nSeg</code> identical
<a href=\"modelica://IDEAS.Fluid.FixedResistances.PlugFlowPipe\">PlugFlowPipe</a>
segments of length <code>length/nSeg</code>. A temperature sensor and a pressure sensor
sit at every segment boundary, i.e. <code>nSeg+1</code> measurement points in total,
available as output vectors <code>T</code> and <code>p</code>.</p>
<p>Note: every PlugFlowPipe adds small mixing volumes (pipe wall capacity) at its ends,
so more segments slightly smear temperature fronts compared to one long pipe.</p>
</html>"));
  end SegmentedPipe;

  model Substation
    "Ideal heat sink with return-temperature-controlled two-way valve"
    extends IDEAS.Fluid.Interfaces.PartialTwoPortInterface(
      m_flow_nominal=Q_flow_nominal/(cp_default*(TSup_nominal - TRet_set)));

    parameter Modelica.Units.SI.HeatFlowRate Q_flow_nominal
      "Design heat demand (positive)";
    parameter Modelica.Units.SI.Temperature TSup_nominal=343.15
      "Design supply temperature";
    parameter Modelica.Units.SI.Temperature TRet_set=318.15
      "Return temperature set point at TSup_nominal";
    parameter Real dTRet_dTSup(unit="1") = 0.4
      "Sensitivity of return set point to supply temperature (0 = constant set point)"
      annotation (Dialog(group="Valve controller"));
    parameter Modelica.Units.SI.TemperatureDifference dTRet_dLoa=30
      "Change of return set point between zero and nominal load (0 = load-independent)"
      annotation (Dialog(group="Valve controller"));
    parameter Modelica.Units.SI.TemperatureDifference dTSupRet_min=5
      "Minimum difference between supply temperature and return set point"
      annotation (Dialog(group="Valve controller"));
    parameter Modelica.Units.SI.PressureDifference dpValve_nominal=30e3
      "Valve pressure drop at nominal flow, fully open";
    parameter Modelica.Units.SI.PressureDifference dpFixed_nominal=10e3
      "Fixed pressure drop of the substation (heat exchanger, piping) at nominal flow";

    parameter Real k(min=0, unit="1/K") = 0.05 "Controller gain"
      annotation (Dialog(group="Valve controller"));
    parameter Modelica.Units.SI.Time Ti=120 "Integral time constant"
      annotation (Dialog(group="Valve controller"));
    parameter Real yMin(min=0, max=1) = 0.02
      "Minimum valve opening (keeps some flow, protects the ideal sink)"
      annotation (Dialog(group="Valve controller"));
    parameter Real yVal_start(min=0, max=1) = 0.5 "Initial valve opening"
      annotation (Dialog(group="Valve controller"));
    parameter Modelica.Units.SI.Temperature TRet_min=278.15
      "Lowest outlet temperature of the heat sink; the extracted heat is capped to reach no lower"
      annotation (Dialog(group="Heat sink"));

    parameter Modelica.Units.SI.SpecificHeatCapacity cp_default=
      Medium.specificHeatCapacityCp(Medium.setState_pTX(
        Medium.p_default, Medium.T_default, Medium.X_default))
      "Specific heat capacity used for sizing";

    Modelica.Blocks.Interfaces.RealInput Q_flow(final unit="W")
      "Heat demand (positive = heat taken from the network)"
      annotation (Placement(transformation(extent={{-20,-20},{20,20}},
        rotation=90, origin={0,-120})));
    Modelica.Blocks.Interfaces.RealOutput TRet(final unit="K", displayUnit="degC")
      "Return temperature leaving the substation"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}},
        rotation=90, origin={60,110})));
    Modelica.Blocks.Interfaces.RealOutput yVal "Valve opening"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}},
        rotation=90, origin={-60,110})));

    IDEAS.Fluid.Sensors.TemperatureTwoPort senTSup(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      tau=0,
      T_start=TSup_nominal) "Supply temperature at substation inlet"
      annotation (Placement(transformation(extent={{-94,-8},{-78,8}})));

    IDEAS.Fluid.Actuators.Valves.TwoWayEqualPercentage val(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      final dpValve_nominal=dpValve_nominal,
      final dpFixed_nominal=dpFixed_nominal,
      final use_strokeTime=false) "Control valve (includes fixed substation resistance)"
      annotation (Placement(transformation(extent={{-70,-10},{-50,10}})));

    IDEAS.Fluid.HeatExchangers.HeaterCooler_u hea(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      final dp_nominal=0,
      final Q_flow_nominal=-Q_flow_nominal,
      T_start=TRet_set) "Ideal heat sink: extracts the prescribed load, capped by the available flow"
      annotation (Placement(transformation(extent={{-20,-10},{0,10}})));

    IDEAS.Fluid.Sensors.TemperatureTwoPort senTRet(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      tau=0,
      T_start=TRet_set) "Return temperature"
      annotation (Placement(transformation(extent={{30,-10},{50,10}})));

    Modelica.Blocks.Math.Gain loaNor(final k=1/Q_flow_nominal)
      "Normalised load"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}}, rotation=90, origin={-40,30})));

    Modelica.Blocks.Sources.RealExpression uHea(
      y=IDEAS.Utilities.Math.Functions.smoothMin(
        loaNor.y,
        IDEAS.Utilities.Math.Functions.smoothMax(port_a.m_flow, 0, 1e-3*m_flow_nominal)
          *cp_default*IDEAS.Utilities.Math.Functions.smoothMax(senTSup.T - TRet_min, 0, 0.1)
          /Q_flow_nominal,
        0.01))
      "Normalised heat extraction: load, capped at what the flow can deliver down to TRet_min"
      annotation (Placement(transformation(extent={{-60,52},{-40,72}})));

    Modelica.Units.SI.HeatFlowRate QUnm_flow = Q_flow + hea.Q_flow
      "Unmet heat demand (positive if the flow is too small for the load)";

    Modelica.Blocks.Sources.RealExpression TRetSet(
      y=min(TRet_set
            + dTRet_dTSup*(senTSup.T - TSup_nominal)
            + dTRet_dLoa*(loaNor.y - 1),
            senTSup.T - dTSupRet_min))
      "Return temperature set point, shifted with supply temperature and load"
      annotation (Placement(transformation(extent={{0,40},{20,60}})));

    IDEAS.Controls.Continuous.LimPID conVal(
      controllerType=Modelica.Blocks.Types.SimpleController.PI,
      final k=k,
      final Ti=Ti,
      final yMax=1,
      final yMin=yMin,
      reverseActing=true,
      initType=Modelica.Blocks.Types.Init.InitialOutput,
      y_start=yVal_start)
      "Opens valve when return temperature is below set point (too little flow)"
      annotation (Placement(transformation(extent={{40,40},{60,60}})));

  equation
    connect(port_a, senTSup.port_a)
      annotation (Line(points={{-100,0},{-94,0}}, color={0,127,255}));
    connect(senTSup.port_b, val.port_a)
      annotation (Line(points={{-78,0},{-70,0}}, color={0,127,255}));
    connect(val.port_b, hea.port_a)
      annotation (Line(points={{-50,0},{-20,0}}, color={0,127,255}));
    connect(hea.port_b, senTRet.port_a)
      annotation (Line(points={{0,0},{30,0}}, color={0,127,255}));
    connect(senTRet.port_b, port_b)
      annotation (Line(points={{50,0},{100,0}}, color={0,127,255}));

    connect(Q_flow, loaNor.u)
      annotation (Line(points={{0,-120},{0,-30},{-40,-30},{-40,18}}, color={0,0,127}));
    connect(uHea.y, hea.u)
      annotation (Line(points={{-39,62},{-30,62},{-30,6},{-22,6}}, color={0,0,127}));

    connect(TRetSet.y, conVal.u_s)
      annotation (Line(points={{21,50},{38,50}}, color={0,0,127}));
    connect(senTRet.T, conVal.u_m)
      annotation (Line(points={{40,11},{40,24},{50,24},{50,38}}, color={0,0,127}));
    connect(conVal.y, val.y)
      annotation (Line(points={{61,50},{70,50},{70,80},{-60,80},{-60,12}}, color={0,0,127}));

    connect(senTRet.T, TRet)
      annotation (Line(points={{40,11},{40,24},{80,24},{80,100},{60,100},{60,110}},
        color={0,0,127}));
    connect(conVal.y, yVal)
      annotation (Line(points={{61,50},{70,50},{70,80},{-60,80},{-60,110}}, color={0,0,127}));

    annotation (Icon(graphics={
          Rectangle(extent={{-100,100},{100,-100}}, lineColor={0,0,0},
            fillColor={255,255,255}, fillPattern=FillPattern.Solid),
          Line(points={{-100,0},{100,0}}, color={0,127,255}),
          Text(extent={{-80,60},{80,20}}, textString="SST"),
          Text(extent={{-150,-60},{150,-100}}, textString="%name", textColor={0,0,255})}),
      Documentation(info="<html>
<p>Simplest substation with a valve: a two-way equal-percentage valve followed by an
ideal heat sink (<code>HeaterCooler_u</code>) that extracts exactly the load
<code>Q_flow</code>. A PI controller positions the valve to hold the return
temperature at its set point; the resulting flow is therefore
<i>m = Q / (cp (T_sup,in - T_ret,set))</i> in steady state.</p>
<p>The set point follows the inlet temperature and the normalised load:
<i>T_ret,set = TRet_set + dTRet_dTSup (T_sup,in - TSup_nominal) + dTRet_dLoa (Q/Q_flow_nominal - 1)</i>,
limited to at most <i>T_sup,in - dTSupRet_min</i>. With <code>dTRet_dTSup = 0</code> and
<code>dTRet_dLoa = 0</code> the set point is constant.</p>
<p>The extracted heat is capped at <i>m cp (T_sup,in - TRet_min)</i>, so the sink outlet cannot
drop below <code>TRet_min</code> when the flow is too small for the load (e.g. load above
design, valve fully open). The shortfall is available as <code>QUnm_flow</code>.</p>
</html>"));
  end Substation;

  model Plant
    "Heat plant: ideal heater with prescribed supply temperature and central dp-controlled pump"
    extends IDEAS.Fluid.Interfaces.PartialTwoPortInterface;

    parameter Modelica.Units.SI.PressureDifference dpPum_nominal
      "Pump head at nominal flow";
    parameter Modelica.Units.SI.AbsolutePressure p_ref=2e5
      "Static pressure at pump inlet (pressure reference / expansion vessel)";
    parameter Modelica.Units.SI.Temperature TSup_nominal=343.15
      "Design supply temperature (initialization)";
    parameter Modelica.Units.SI.Temperature TRet_nominal=313.15
      "Design return temperature (initialization)";

    Modelica.Blocks.Interfaces.RealInput TSupSet(final unit="K", displayUnit="degC")
      "Supply temperature set point"
      annotation (Placement(transformation(extent={{-140,40},{-100,80}})));
    Modelica.Blocks.Interfaces.RealInput dpPum(final unit="Pa")
      "Pump head set point"
      annotation (Placement(transformation(extent={{-20,-20},{20,20}},
        rotation=-90, origin={-30,120})));
    Modelica.Blocks.Interfaces.RealOutput Q_flow(final unit="W")
      "Heat supplied by the plant"
      annotation (Placement(transformation(extent={{100,20},{120,40}})));
    Modelica.Blocks.Interfaces.RealOutput PPum(final unit="W")
      "Pump electrical power"
      annotation (Placement(transformation(extent={{100,50},{120,70}})));

    IDEAS.Fluid.Sources.Boundary_pT bou(
      redeclare final package Medium = Medium,
      final p=p_ref,
      final T=TRet_nominal,
      nPorts=1) "Pressure reference"
      annotation (Placement(transformation(extent={{-80,-50},{-60,-30}})));

    IDEAS.Fluid.Movers.FlowControlled_dp pum(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final dp_nominal=dpPum_nominal,
      final allowFlowReversal=allowFlowReversal,
      inputType=IDEAS.Fluid.Types.InputType.Continuous,
      use_riseTime=false,
      addPowerToMedium=false,
      energyDynamics=Modelica.Fluid.Types.Dynamics.SteadyState)
      "Central circulation pump"
      annotation (Placement(transformation(extent={{-40,-10},{-20,10}})));

    IDEAS.Fluid.HeatExchangers.PrescribedOutlet hea(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      final dp_nominal=0,
      final use_X_wSet=false,
      final QMin_flow=0,
      T_start=TSup_nominal) "Ideal heater: outlet at TSupSet, can only heat"
      annotation (Placement(transformation(extent={{10,-10},{30,10}})));

    IDEAS.Fluid.Sensors.MassFlowRate senMasFlo(
      redeclare final package Medium = Medium,
      final allowFlowReversal=allowFlowReversal) "Network mass flow rate"
      annotation (Placement(transformation(extent={{50,-10},{70,10}})));

  equation
    connect(port_a, pum.port_a)
      annotation (Line(points={{-100,0},{-40,0}}, color={0,127,255}));
    connect(bou.ports[1], pum.port_a)
      annotation (Line(points={{-60,-40},{-50,-40},{-50,0},{-40,0}}, color={0,127,255}));
    connect(pum.port_b, hea.port_a)
      annotation (Line(points={{-20,0},{10,0}}, color={0,127,255}));
    connect(hea.port_b, senMasFlo.port_a)
      annotation (Line(points={{30,0},{50,0}}, color={0,127,255}));
    connect(senMasFlo.port_b, port_b)
      annotation (Line(points={{70,0},{100,0}}, color={0,127,255}));

    connect(TSupSet, hea.TSet)
      annotation (Line(points={{-120,60},{0,60},{0,8},{8,8}}, color={0,0,127}));
    connect(dpPum, pum.dp_in)
      annotation (Line(points={{-30,120},{-30,12}}, color={0,0,127}));
    connect(hea.Q_flow, Q_flow)
      annotation (Line(points={{31,8},{40,8},{40,30},{110,30}}, color={0,0,127}));
    connect(pum.P, PPum)
      annotation (Line(points={{-19,9},{-16,9},{-16,70},{90,70},{90,60},{110,60}},
        color={0,0,127}));

    annotation (Icon(graphics={
          Rectangle(extent={{-100,100},{100,-100}}, lineColor={0,0,0},
            fillColor={255,170,170}, fillPattern=FillPattern.Solid),
          Text(extent={{-80,40},{80,-40}}, textString="Plant"),
          Text(extent={{-150,-60},{150,-100}}, textString="%name", textColor={0,0,255})}),
      Documentation(info="<html>
<p><code>port_a</code>: return from network, <code>port_b</code>: supply to network.
The boundary at the pump inlet fixes the static pressure of the closed loop.</p>
</html>"));
  end Plant;

  model EndOfLineBypass
    "Thermostatic end-of-line bypass: opens when the supply temperature at the end of the line drops below a set point"
    extends IDEAS.Fluid.Interfaces.PartialTwoPortInterface;

    parameter Modelica.Units.SI.Temperature TSet=333.15
      "Bypass opens when TMea falls below this temperature";
    parameter Modelica.Units.SI.PressureDifference dpValve_nominal
      "Valve pressure drop at m_flow_nominal, fully open (typically the worst-point dp set point)";
    parameter Real k(min=0, unit="1/K") = 0.1 "Controller gain"
      annotation (Dialog(group="Controller"));
    parameter Modelica.Units.SI.Time Ti=300 "Integral time constant"
      annotation (Dialog(group="Controller"));
    parameter Real y_start(min=0, max=1) = 0 "Initial valve opening"
      annotation (Dialog(group="Controller"));

    Modelica.Blocks.Interfaces.RealInput TMea(final unit="K", displayUnit="degC")
      "Measured supply temperature at the end of the line"
      annotation (Placement(transformation(extent={{-20,-20},{20,20}},
        rotation=90, origin={0,-120})));
    Modelica.Blocks.Interfaces.RealOutput yVal "Bypass valve opening"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}},
        rotation=90, origin={-60,110})));

    IDEAS.Fluid.Actuators.Valves.TwoWayLinear val(
      redeclare final package Medium = Medium,
      final m_flow_nominal=m_flow_nominal,
      final allowFlowReversal=allowFlowReversal,
      final dpValve_nominal=dpValve_nominal,
      final use_strokeTime=false) "Bypass valve"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}})));

    Modelica.Blocks.Sources.Constant TSetCon(final k=TSet) "Temperature set point"
      annotation (Placement(transformation(extent={{-80,40},{-60,60}})));

    IDEAS.Controls.Continuous.LimPID con(
      controllerType=Modelica.Blocks.Types.SimpleController.PI,
      final k=k,
      final Ti=Ti,
      final yMax=1,
      final yMin=0,
      reverseActing=true,
      initType=Modelica.Blocks.Types.Init.InitialOutput,
      final y_start=y_start)
      "Opens bypass when supply temperature is below set point"
      annotation (Placement(transformation(extent={{-40,40},{-20,60}})));

  equation
    connect(port_a, val.port_a)
      annotation (Line(points={{-100,0},{-10,0}}, color={0,127,255}));
    connect(val.port_b, port_b)
      annotation (Line(points={{10,0},{100,0}}, color={0,127,255}));
    connect(TSetCon.y, con.u_s)
      annotation (Line(points={{-59,50},{-42,50}}, color={0,0,127}));
    connect(TMea, con.u_m)
      annotation (Line(points={{0,-120},{0,-40},{-50,-40},{-50,30},{-30,30},{-30,38}},
        color={0,0,127}));
    connect(con.y, val.y)
      annotation (Line(points={{-19,50},{0,50},{0,12}}, color={0,0,127}));
    connect(con.y, yVal)
      annotation (Line(points={{-19,50},{-10,50},{-10,90},{-60,90},{-60,110}},
        color={0,0,127}));

    annotation (Icon(graphics={
          Rectangle(extent={{-100,100},{100,-100}}, lineColor={0,0,0},
            fillColor={255,255,255}, fillPattern=FillPattern.Solid),
          Line(points={{-100,0},{100,0}}, color={0,127,255}),
          Polygon(points={{-40,30},{-40,-30},{0,0},{-40,30}}, lineColor={0,0,0},
            fillColor={255,255,255}, fillPattern=FillPattern.Solid),
          Polygon(points={{40,30},{40,-30},{0,0},{40,30}}, lineColor={0,0,0},
            fillColor={255,255,255}, fillPattern=FillPattern.Solid),
          Text(extent={{-80,80},{80,40}}, textString="EOL"),
          Text(extent={{-150,-60},{150,-100}}, textString="%name", textColor={0,0,255})}),
      Documentation(info="<html>
<p>Linear two-way valve between supply and return at the end of the line.
A PI controller opens it when the measured supply temperature <code>TMea</code>
drops below <code>TSet</code>, so that warm water keeps circulating to the far end
of the network at low load. Sizing: with <code>dpValve_nominal</code> equal to the
worst-point dp set point, the fully open valve passes <code>m_flow_nominal</code>.</p>
</html>"));
  end EndOfLineBypass;

  model Network
    "Two-pipe line network: plant, nSub substations in parallel, optional end-of-line bypass, central pump with worst-point dp control"

    replaceable package Medium = IDEAS.Media.Water constrainedby
      Modelica.Media.Interfaces.PartialMedium;

    // Topology
    parameter Integer nSub(min=1) = 2
      "Number of substations (= number of pipe sections per direction)"
      annotation (Evaluate=true, Dialog(group="Topology"));
    parameter Boolean use_bypass=true "= true, include end-of-line bypass"
      annotation (Evaluate=true, Dialog(group="Topology"));

    // Design
    parameter Modelica.Units.SI.Temperature TSup_nominal=343.15 "Design supply temperature"
      annotation (Dialog(group="Design"));
    parameter Modelica.Units.SI.Temperature TRet_set=313.15 "Return temperature set point"
      annotation (Dialog(group="Design"));
    parameter Modelica.Units.SI.HeatFlowRate Q_nominal[nSub]=fill(100e3, nSub)
      "Design load of each substation" annotation (Dialog(group="Design"));
    parameter Modelica.Units.SI.Temperature TGro=283.15 "Undisturbed ground temperature"
      annotation (Dialog(group="Design"));
    parameter Boolean allowFlowReversal=true
      "= false to simplify equations if flow is known to be one-directional"
      annotation (Dialog(group="Design"));

    // Pipes
    parameter Modelica.Units.SI.Length L[nSub]=fill(300, nSub)
      "Length of section i (one way), from node i-1 (plant = node 0) to substation i"
      annotation (Dialog(group="Pipes"));
    parameter Integer nSeg=3 "Number of identical segments in every pipe section"
      annotation (Evaluate=true, Dialog(group="Pipes"));
    parameter Modelica.Units.SI.Velocity v_design=0.6
      "Design flow velocity used to size the pipe diameters"
      annotation (Dialog(group="Pipes"));
    parameter Modelica.Units.SI.Length dh[nSub]=
      {sqrt(4*mSec_nominal[i]/(rho_default*Modelica.Constants.pi*v_design)) for i in 1:nSub}
      "Inner diameter of each section (default: sized for v_design)"
      annotation (Dialog(group="Pipes"));
    parameter Modelica.Units.SI.Length dIns=0.04 "Insulation thickness"
      annotation (Dialog(group="Pipes"));
    parameter Modelica.Units.SI.ThermalConductivity kIns=0.026 "Insulation conductivity"
      annotation (Dialog(group="Pipes"));

    // Bypass
    parameter Modelica.Units.SI.Temperature TBypSet=333.15
      "Bypass opens below this supply temperature at the end of the line"
      annotation (Dialog(group="End-of-line bypass", enable=use_bypass));
    parameter Real fracByp(min=0) = 0.05
      "Nominal bypass flow as a fraction of the total substation design flow"
      annotation (Dialog(group="End-of-line bypass", enable=use_bypass));

    // Pump control
    parameter Modelica.Units.SI.PressureDifference dpSetWorst=80e3
      "Differential pressure set point at the last substation (worst point)"
      annotation (Dialog(group="Pump control"));
    parameter Modelica.Units.SI.PressureDifference dpPum_nominal=150e3
      "Nominal pump head" annotation (Dialog(group="Pump control"));
    parameter Modelica.Units.SI.PressureDifference dpPum_max=200e3
      "Maximum pump head" annotation (Dialog(group="Pump control"));

    final parameter Modelica.Units.SI.MassFlowRate mSub_nominal[nSub]=sub.m_flow_nominal
      "Design flow of each substation";
    final parameter Modelica.Units.SI.MassFlowRate mByp_nominal=
      if use_bypass then fracByp*sum(mSub_nominal) else 0 "Design bypass flow";
    final parameter Modelica.Units.SI.MassFlowRate mSec_nominal[nSub]=
      {sum(mSub_nominal[i:nSub]) + mByp_nominal for i in 1:nSub}
      "Design flow in pipe section i (all downstream substations + bypass)";
    final parameter Modelica.Units.SI.Density rho_default=Medium.density(
      Medium.setState_pTX(Medium.p_default, Medium.T_default, Medium.X_default));

    // External inputs
    Modelica.Blocks.Interfaces.RealInput TSupSet(final unit="K", displayUnit="degC")
      "Plant supply temperature set point"
      annotation (Placement(transformation(extent={{-140,-14},{-100,26}})));
    Modelica.Blocks.Interfaces.RealInput Q_flow[nSub](each final unit="W")
      "Load of each substation"
      annotation (Placement(transformation(extent={{-140,-60},{-100,-20}})));

    // Plant
    Plant pla(
      redeclare final package Medium = Medium,
      final m_flow_nominal=mSec_nominal[1],
      final dpPum_nominal=dpPum_nominal,
      final TSup_nominal=TSup_nominal,
      final TRet_nominal=TRet_set,
      final allowFlowReversal=allowFlowReversal)
      annotation (Placement(transformation(extent={{-80,-10},{-60,10}})));

    // Pipes: section i connects node i-1 to node i (node 0 = plant)
    SegmentedPipe pipSup[nSub](
      redeclare each final package Medium = Medium,
      final m_flow_nominal=mSec_nominal,
      each final allowFlowReversal=allowFlowReversal,
      each final nSeg=nSeg,
      final length=L,
      final dh=dh,
      each final dIns=dIns,
      each final kIns=kIns,
      each final T_start=TSup_nominal) "Supply sections"
      annotation (Placement(transformation(extent={{-40,30},{-20,50}})));
    SegmentedPipe pipRet[nSub](
      redeclare each final package Medium = Medium,
      final m_flow_nominal=mSec_nominal,
      each final allowFlowReversal=allowFlowReversal,
      each final nSeg=nSeg,
      final length=L,
      final dh=dh,
      each final dIns=dIns,
      each final kIns=kIns,
      each final T_start=TRet_set) "Return sections (flow from node i towards node i-1)"
      annotation (Placement(transformation(extent={{-20,-30},{-40,-50}})));

    Modelica.Thermal.HeatTransfer.Sources.FixedTemperature groSup(final T=TGro)
      "Ground around supply pipes"
      annotation (Placement(transformation(extent={{-60,60},{-40,80}})));
    Modelica.Thermal.HeatTransfer.Sources.FixedTemperature groRet(final T=TGro)
      "Ground around return pipes"
      annotation (Placement(transformation(extent={{-60,-80},{-40,-60}})));

    // Substations
    Substation sub[nSub](
      redeclare each final package Medium = Medium,
      each final allowFlowReversal=allowFlowReversal,
      final Q_flow_nominal=Q_nominal,
      each final TSup_nominal=TSup_nominal,
      each final TRet_set=TRet_set) "Substations, sub[i] at node i"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}}, rotation=-90, origin={10,0})));

    // End-of-line bypass
    EndOfLineBypass byp(
      redeclare final package Medium = Medium,
      final m_flow_nominal=max(mByp_nominal, 1e-3),
      final allowFlowReversal=allowFlowReversal,
      final dpValve_nominal=dpSetWorst,
      final TSet=TBypSet) if use_bypass
      "End-of-line bypass at the last node"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}}, rotation=-90, origin={60,0})));

    // Worst-point differential pressure control of the central pump
    IDEAS.Fluid.Sensors.RelativePressure senDpWorst(
      redeclare final package Medium = Medium)
      "Supply-return differential pressure at the last substation"
      annotation (Placement(transformation(extent={{-10,-10},{10,10}}, rotation=-90, origin={90,0})));
    Modelica.Blocks.Math.Gain dpNor(final k=1/dpSetWorst)
      "Normalised measured dp"
      annotation (Placement(transformation(extent={{100,50},{120,70}})));
    Modelica.Blocks.Sources.Constant one(final k=1) "Normalised set point"
      annotation (Placement(transformation(extent={{140,100},{120,120}})));
    IDEAS.Controls.Continuous.LimPID conPum(
      controllerType=Modelica.Blocks.Types.SimpleController.PI,
      k=0.5,
      Ti=30,
      yMax=1,
      yMin=0.05,
      reverseActing=true,
      initType=Modelica.Blocks.Types.Init.InitialOutput,
      y_start=dpPum_nominal/dpPum_max)
      "Raises pump head when worst-point dp is below set point"
      annotation (Placement(transformation(extent={{100,100},{80,120}})));
    Modelica.Blocks.Math.Gain dpPumSet(final k=dpPum_max) "Pump head set point"
      annotation (Placement(transformation(extent={{0,100},{-20,120}})));

    // Key results
    // Outputs (assigned in the equation section)
    Modelica.Blocks.Interfaces.RealOutput QPla_flow(final unit="W")
      "Heat supplied by the plant"
      annotation (Placement(transformation(extent={{105,30},{115,40}})));
    Modelica.Blocks.Interfaces.RealOutput PPum(final unit="W")
      "Pump electrical power"
      annotation (Placement(transformation(extent={{105,15},{115,25}})));
    Modelica.Blocks.Interfaces.RealOutput QLos_flow(final unit="W")
      "Total network heat loss"
      annotation (Placement(transformation(extent={{105,0},{115,10}})));
    Modelica.Blocks.Interfaces.RealOutput TRetPla(final unit="K", displayUnit="degC")
      "Return temperature arriving at the plant"
      annotation (Placement(transformation(extent={{105,-15},{115,-5}})));
    Modelica.Blocks.Interfaces.RealOutput TSupSub[nSub](each final unit="K", each displayUnit="degC")
      "Supply temperature arriving at each substation"
      annotation (Placement(transformation(extent={{105,-50},{115,-40}})));
    Modelica.Blocks.Interfaces.RealOutput TRetSub[nSub](each final unit="K", each displayUnit="degC")
      "Return temperature leaving each substation"
      annotation (Placement(transformation(extent={{105,-70},{115,-60}})));
    Modelica.Blocks.Interfaces.RealOutput mSub_flow[nSub](each final unit="kg/s")
      "Mass flow rate through each substation"
      annotation (Placement(transformation(extent={{105,-90},{115,-80}})));
    Modelica.Blocks.Interfaces.RealOutput TRetPip[nSub, nSeg + 1](
      each final unit="K", each displayUnit="degC")
      "Return pipe i: temperatures at segment ends (1 = inlet at node i, nSeg+1 = outlet towards plant)"
      annotation (Placement(transformation(extent={{-5,-5},{5,5}}, rotation=-90, origin={20,-110})));
    Modelica.Blocks.Interfaces.RealOutput mRetPip_flow[nSub](each final unit="kg/s")
      "Return pipe i: mass flow rate"
      annotation (Placement(transformation(extent={{-5,-5},{5,5}}, rotation=-90, origin={40,-110})));
    Modelica.Blocks.Interfaces.RealOutput TSupPip[nSub, nSeg + 1](
      each final unit="K", each displayUnit="degC")
      "Supply pipe i: temperatures at segment ends (1 = inlet, nSeg+1 = outlet at node i)"
      annotation (Placement(transformation(extent={{-5,-5},{5,5}}, rotation=-90, origin={60,-110})));
    Modelica.Blocks.Interfaces.RealOutput mSupPip_flow[nSub](each final unit="kg/s")
      "Supply pipe i: mass flow rate"
      annotation (Placement(transformation(extent={{-5,-5},{5,5}}, rotation=-90, origin={80,-110})));

  equation
    // Plant to first section
    connect(pla.port_b, pipSup[1].port_a)
      annotation (Line(points={{-60,0},{-50,0},{-50,40},{-40,40}}, color={0,127,255}, thickness=0.5));
    connect(pipRet[1].port_b, pla.port_a)
      annotation (Line(points={{-40,-40},{-90,-40},{-90,0},{-80,0}}, color={0,127,255}, thickness=0.5));

    // Node i: end of supply section i, substation i, start of return section i
    for i in 1:nSub loop
      connect(pipSup[i].port_b, sub[i].port_a)
        annotation (Line(points={{-20,40},{10,40},{10,10}}, color={0,127,255}, thickness=0.5));
      connect(sub[i].port_b, pipRet[i].port_a)
        annotation (Line(points={{10,-10},{10,-40},{-20,-40}}, color={0,127,255}, thickness=0.5));
      connect(groSup.port, pipSup[i].heatPort)
        annotation (Line(points={{-40,70},{-30,70},{-30,50}}, color={191,0,0}));
      connect(groRet.port, pipRet[i].heatPort)
        annotation (Line(points={{-40,-70},{-30,-70},{-30,-50}}, color={191,0,0}));
    end for;

    // Chain the sections: node i -> section i+1
    for i in 1:nSub - 1 loop
      connect(pipSup[i].port_b, pipSup[i + 1].port_a)
        annotation (Line(points={{-20,40},{-14,40},{-14,24},{-46,24},{-46,40},{-40,40}},
          color={0,127,255}, thickness=0.5, pattern=LinePattern.Dash));
      connect(pipRet[i + 1].port_b, pipRet[i].port_a)
        annotation (Line(points={{-40,-40},{-46,-40},{-46,-24},{-14,-24},{-14,-40},{-20,-40}},
          color={0,127,255}, thickness=0.5, pattern=LinePattern.Dash));
    end for;

    // End-of-line bypass at the last node
    connect(pipSup[nSub].port_b, byp.port_a)
      annotation (Line(points={{-20,40},{60,40},{60,10}}, color={0,127,255}));
    connect(byp.port_b, pipRet[nSub].port_a)
      annotation (Line(points={{60,-10},{60,-40},{-20,-40}}, color={0,127,255}));
    connect(pipSup[nSub].T[nSeg + 1], byp.TMea)
      annotation (Line(points={{-19,46},{-8,46},{-8,20},{40,20},{40,0},{48,0}},
        color={0,0,127}));

    // Inputs
    connect(TSupSet, pla.TSupSet)
      annotation (Line(points={{-120,6},{-82,6}}, color={0,0,127}));
    connect(Q_flow, sub.Q_flow)
      annotation (Line(points={{-120,-40},{-100,-40},{-100,-20},{-6,-20},{-6,0},{-2,0}},
        color={0,0,127}));

    // Pump control
    connect(senDpWorst.port_a, sub[nSub].port_a)
      annotation (Line(points={{90,10},{90,40},{10,40},{10,10}}, color={0,127,255}));
    connect(senDpWorst.port_b, sub[nSub].port_b)
      annotation (Line(points={{90,-10},{90,-40},{10,-40},{10,-10}}, color={0,127,255}));
    connect(senDpWorst.p_rel, dpNor.u)
      annotation (Line(points={{81,0},{76,0},{76,60},{98,60}}, color={0,0,127}));
    connect(one.y, conPum.u_s)
      annotation (Line(points={{119,110},{102,110}}, color={0,0,127}));
    connect(dpNor.y, conPum.u_m)
      annotation (Line(points={{121,60},{130,60},{130,90},{90,90},{90,98}}, color={0,0,127}));
    connect(conPum.y, dpPumSet.u)
      annotation (Line(points={{79,110},{2,110}}, color={0,0,127}));
    connect(dpPumSet.y, pla.dpPum)
      annotation (Line(points={{-21,110},{-73,110},{-73,12}}, color={0,0,127}));

    // Outputs
    QPla_flow = pla.Q_flow;
    PPum = pla.PPum;
    QLos_flow = sum(pipSup.QLos_flow) + sum(pipRet.QLos_flow);
    TRetPla = pipRet[1].T[nSeg + 1];
    TSupSub = {pipSup[i].T[nSeg + 1] for i in 1:nSub};
    TRetSub = sub.TRet;
    mSub_flow = sub.m_flow;
    mSupPip_flow = pipSup.m_flow;
    mRetPip_flow = pipRet.m_flow;
    for i in 1:nSub loop
      TSupPip[i, :] = pipSup[i].T;
      TRetPip[i, :] = pipRet[i].T;
    end for;

    annotation (
      Diagram(coordinateSystem(extent={{-140,-120},{140,140}}), graphics={
          Text(extent={{-14,54},{26,44}}, textColor={238,46,47}, textString="Supply",
            horizontalAlignment=TextAlignment.Left),
          Text(extent={{-14,-44},{26,-54}}, textColor={28,108,200}, textString="Return",
            horizontalAlignment=TextAlignment.Left),
          Text(extent={{20,132},{100,122}}, textColor={95,95,95},
            textString="Worst-point dp control"),
          Text(extent={{-48,19},{-12,13}}, textColor={95,95,95},
            textString="dashed: i -> i+1"),
          Text(extent={{44,-46},{104,-56}}, textColor={95,95,95},
            textString="at node nSub"),
          Text(extent={{60,-92},{140,-100}}, textColor={95,95,95},
            textString="outputs: see equation section")}),
      Icon(graphics={
          Rectangle(extent={{-100,100},{100,-100}}, lineColor={0,0,0},
            fillColor={255,255,255}, fillPattern=FillPattern.Solid),
          Line(points={{-70,40},{80,40},{80,10}}, color={238,46,47}, thickness=1),
          Line(points={{-70,-40},{80,-40},{80,-10}}, color={28,108,200}, thickness=1),
          Line(points={{-10,40},{-10,10}}, color={238,46,47}, thickness=1),
          Line(points={{-10,-40},{-10,-10}}, color={28,108,200}, thickness=1),
          Line(points={{40,40},{40,10}}, color={238,46,47}, thickness=1),
          Line(points={{40,-40},{40,-10}}, color={28,108,200}, thickness=1),
          Rectangle(extent={{-90,20},{-50,-20}}, fillColor={255,170,170},
            fillPattern=FillPattern.Solid),
          Line(points={{-70,40},{-70,20}}, color={238,46,47}, thickness=1),
          Line(points={{-70,-40},{-70,-20}}, color={28,108,200}, thickness=1),
          Rectangle(extent={{-20,10},{0,-10}}, fillColor={215,215,215},
            fillPattern=FillPattern.Solid),
          Rectangle(extent={{30,10},{50,-10}}, fillColor={215,215,215},
            fillPattern=FillPattern.Solid),
          Line(points={{80,10},{80,-10}}, color={0,0,0}, pattern=LinePattern.Dot),
          Text(extent={{-100,90},{100,60}}, textString="nSub=%nSub")}),
      Documentation(info="<html>
<pre>
 Plant ==pipSup[1]==+==pipSup[2]==+ ... ==pipSup[nSub]==+------+
                    |             |                    |      |
                  sub[1]        sub[2]   ...       sub[nSub]  byp (end-of-line bypass)
                    |             |                    |      |
 Plant ==pipRet[1]==+==pipRet[2]==+ ... ==pipRet[nSub]==+------+
</pre>
<p><code>nSub</code> substations in parallel along a single line. Pipe section
<code>i</code> runs from node <code>i-1</code> (node 0 = plant) to node <code>i</code>,
where substation <code>i</code> is connected. Section design flows are the sum of all
downstream substation design flows plus the bypass; diameters are sized for
<code>v_design</code> unless <code>dh</code> is given.</p>
<p>The central pump keeps the supply-return dp at the last substation at
<code>dpSetWorst</code>. The optional thermostatic end-of-line bypass connects supply
and return at the last node and opens when the supply temperature arriving there
drops below <code>TBypSet</code>.</p>
<p>All pipe sections use the same number of segments <code>nSeg</code>, because
elements of a component array must have the same structure.</p>
</html>"));
  end Network;

  package Utilities "Signal routing helpers"
    extends Modelica.Icons.UtilitiesPackage;

    block Collect10 "Collects 10 scalar inputs and outputs the first nOut of them as a smoothed vector"
      extends Modelica.Blocks.Icons.Block;
      parameter Integer nOut(min=1, max=10) = 10 "Number of inputs passed on"
        annotation (Evaluate=true);
      parameter Boolean use_filter = true "= true, to smooth inputs with a first-order lag"
        annotation (Evaluate=true);
      parameter Modelica.Units.SI.Time tau(min=Modelica.Constants.small) = 300
        "Filter time constant"
        annotation (Dialog(enable=use_filter));
      parameter Real uMin = -Modelica.Constants.inf "Lower limit of all inputs"
        annotation (Dialog(group="Limits"));
      parameter Real uMax[nOut] = fill(Modelica.Constants.inf, nOut) "Upper limit of each input"
        annotation (Dialog(group="Limits"));
      Modelica.Blocks.Interfaces.RealInput u1 "Input 1"
        annotation (Placement(transformation(extent={{-130,80},{-110,100}})));
      Modelica.Blocks.Interfaces.RealInput u2 "Input 2"
        annotation (Placement(transformation(extent={{-130,60},{-110,80}})));
      Modelica.Blocks.Interfaces.RealInput u3 "Input 3"
        annotation (Placement(transformation(extent={{-130,40},{-110,60}})));
      Modelica.Blocks.Interfaces.RealInput u4 "Input 4"
        annotation (Placement(transformation(extent={{-130,20},{-110,40}})));
      Modelica.Blocks.Interfaces.RealInput u5 "Input 5"
        annotation (Placement(transformation(extent={{-130,0},{-110,20}})));
      Modelica.Blocks.Interfaces.RealInput u6 "Input 6"
        annotation (Placement(transformation(extent={{-130,-20},{-110,0}})));
      Modelica.Blocks.Interfaces.RealInput u7 "Input 7"
        annotation (Placement(transformation(extent={{-130,-40},{-110,-20}})));
      Modelica.Blocks.Interfaces.RealInput u8 "Input 8"
        annotation (Placement(transformation(extent={{-130,-60},{-110,-40}})));
      Modelica.Blocks.Interfaces.RealInput u9 "Input 9"
        annotation (Placement(transformation(extent={{-130,-80},{-110,-60}})));
      Modelica.Blocks.Interfaces.RealInput u10 "Input 10"
        annotation (Placement(transformation(extent={{-130,-100},{-110,-80}})));
      Modelica.Blocks.Interfaces.RealOutput y[nOut] "Inputs 1..nOut as vector, limited and optionally smoothed"
        annotation (Placement(transformation(extent={{100,-10},{120,10}})));
    protected
      Real uAll[10] = {u1, u2, u3, u4, u5, u6, u7, u8, u9, u10};
      Real uLim[nOut] = {min(max(uAll[i], uMin), uMax[i]) for i in 1:nOut}
        "Inputs 1..nOut, limited to [uMin, uMax]";
    initial equation
      if use_filter then
        y = uLim;
      end if;
    equation
      if use_filter then
        tau*der(y) = uLim - y;
      else
        y = uLim;
      end if;
      annotation (Icon(graphics={
            Line(points={{-100,90},{0,0},{100,0}}, color={0,0,127}),
            Line(points={{-100,-90},{0,0}}, color={0,0,127}, pattern=LinePattern.Dash),
            Text(extent={{-90,-20},{90,-60}}, textString="1..%nOut")}),
        Documentation(info="<html>
<p>Inputs <code>nOut+1..10</code> are ignored. Input <code>i</code> is limited to
<code>[uMin, uMax[i]]</code> before smoothing.</p>
<p>If <code>use_filter=true</code>, the outputs follow the inputs through a first-order lag
with time constant <code>tau</code>, initialized in steady state (<code>y = u</code> at start).</p>
</html>"));
    end Collect10;

    block Distribute10 "Distributes a vector of length nIn to 10 scalar outputs; unused outputs are set to yUnused"
      extends Modelica.Blocks.Icons.Block;
      parameter Integer nIn(min=1, max=10) = 10 "Length of input vector"
        annotation (Evaluate=true);
      parameter Real yUnused=0 "Value of outputs nIn+1..10";
      Modelica.Blocks.Interfaces.RealInput u[nIn] "Input vector"
        annotation (Placement(transformation(extent={{-140,-20},{-100,20}})));
      Modelica.Blocks.Interfaces.RealOutput y1 "Output 1"
        annotation (Placement(transformation(extent={{100,80},{120,100}})));
      Modelica.Blocks.Interfaces.RealOutput y2 "Output 2"
        annotation (Placement(transformation(extent={{100,60},{120,80}})));
      Modelica.Blocks.Interfaces.RealOutput y3 "Output 3"
        annotation (Placement(transformation(extent={{100,40},{120,60}})));
      Modelica.Blocks.Interfaces.RealOutput y4 "Output 4"
        annotation (Placement(transformation(extent={{100,20},{120,40}})));
      Modelica.Blocks.Interfaces.RealOutput y5 "Output 5"
        annotation (Placement(transformation(extent={{100,0},{120,20}})));
      Modelica.Blocks.Interfaces.RealOutput y6 "Output 6"
        annotation (Placement(transformation(extent={{100,-20},{120,0}})));
      Modelica.Blocks.Interfaces.RealOutput y7 "Output 7"
        annotation (Placement(transformation(extent={{100,-40},{120,-20}})));
      Modelica.Blocks.Interfaces.RealOutput y8 "Output 8"
        annotation (Placement(transformation(extent={{100,-60},{120,-40}})));
      Modelica.Blocks.Interfaces.RealOutput y9 "Output 9"
        annotation (Placement(transformation(extent={{100,-80},{120,-60}})));
      Modelica.Blocks.Interfaces.RealOutput y10 "Output 10"
        annotation (Placement(transformation(extent={{100,-100},{120,-80}})));
    protected
      Real yAll[10] = cat(1, u, fill(yUnused, 10 - nIn));
    equation
      y1 = yAll[1];
      y2 = yAll[2];
      y3 = yAll[3];
      y4 = yAll[4];
      y5 = yAll[5];
      y6 = yAll[6];
      y7 = yAll[7];
      y8 = yAll[8];
      y9 = yAll[9];
      y10 = yAll[10];
      annotation (Icon(graphics={
            Line(points={{-100,0},{0,0},{100,90}}, color={0,0,127}),
            Line(points={{0,0},{100,-90}}, color={0,0,127}, pattern=LinePattern.Dash),
            Text(extent={{-90,-20},{90,-60}}, textString="1..%nIn")}),
        Documentation(info="<html><p>Outputs <code>nIn+1..10</code> are set to <code>yUnused</code>.</p></html>"));
    end Distribute10;

    block DistributePipe10x4
      "Distributes per-pipe mass flow m[nIn] and 4 temperatures T[nIn,4] (pipes with 3 segments) to scalar outputs"
      extends Modelica.Blocks.Icons.Block;
      parameter Integer nIn(min=1, max=10) = 10 "Number of pipes"
        annotation (Evaluate=true);
      parameter Real mUnused=0 "Mass flow outputs of pipes nIn+1..10";
      parameter Real TUnused=0 "Temperature outputs of pipes nIn+1..10";
      Modelica.Blocks.Interfaces.RealInput m[nIn] "Mass flow rate of each pipe"
        annotation (Placement(transformation(extent={{-140,20},{-100,60}})));
      Modelica.Blocks.Interfaces.RealInput T[nIn, 4]
        "Temperatures at the 4 segment ends of each pipe"
        annotation (Placement(transformation(extent={{-140,-60},{-100,-20}})));
      Modelica.Blocks.Interfaces.RealOutput m1
        annotation (Placement(transformation(extent={{100,96},{104,100}})));
      Modelica.Blocks.Interfaces.RealOutput T1_1
        annotation (Placement(transformation(extent={{100,92},{104,96}})));
      Modelica.Blocks.Interfaces.RealOutput T1_2
        annotation (Placement(transformation(extent={{100,88},{104,92}})));
      Modelica.Blocks.Interfaces.RealOutput T1_3
        annotation (Placement(transformation(extent={{100,84},{104,88}})));
      Modelica.Blocks.Interfaces.RealOutput T1_4
        annotation (Placement(transformation(extent={{100,80},{104,84}})));
      Modelica.Blocks.Interfaces.RealOutput m2
        annotation (Placement(transformation(extent={{100,76},{104,80}})));
      Modelica.Blocks.Interfaces.RealOutput T2_1
        annotation (Placement(transformation(extent={{100,72},{104,76}})));
      Modelica.Blocks.Interfaces.RealOutput T2_2
        annotation (Placement(transformation(extent={{100,68},{104,72}})));
      Modelica.Blocks.Interfaces.RealOutput T2_3
        annotation (Placement(transformation(extent={{100,64},{104,68}})));
      Modelica.Blocks.Interfaces.RealOutput T2_4
        annotation (Placement(transformation(extent={{100,60},{104,64}})));
      Modelica.Blocks.Interfaces.RealOutput m3
        annotation (Placement(transformation(extent={{100,56},{104,60}})));
      Modelica.Blocks.Interfaces.RealOutput T3_1
        annotation (Placement(transformation(extent={{100,52},{104,56}})));
      Modelica.Blocks.Interfaces.RealOutput T3_2
        annotation (Placement(transformation(extent={{100,48},{104,52}})));
      Modelica.Blocks.Interfaces.RealOutput T3_3
        annotation (Placement(transformation(extent={{100,44},{104,48}})));
      Modelica.Blocks.Interfaces.RealOutput T3_4
        annotation (Placement(transformation(extent={{100,40},{104,44}})));
      Modelica.Blocks.Interfaces.RealOutput m4
        annotation (Placement(transformation(extent={{100,36},{104,40}})));
      Modelica.Blocks.Interfaces.RealOutput T4_1
        annotation (Placement(transformation(extent={{100,32},{104,36}})));
      Modelica.Blocks.Interfaces.RealOutput T4_2
        annotation (Placement(transformation(extent={{100,28},{104,32}})));
      Modelica.Blocks.Interfaces.RealOutput T4_3
        annotation (Placement(transformation(extent={{100,24},{104,28}})));
      Modelica.Blocks.Interfaces.RealOutput T4_4
        annotation (Placement(transformation(extent={{100,20},{104,24}})));
      Modelica.Blocks.Interfaces.RealOutput m5
        annotation (Placement(transformation(extent={{100,16},{104,20}})));
      Modelica.Blocks.Interfaces.RealOutput T5_1
        annotation (Placement(transformation(extent={{100,12},{104,16}})));
      Modelica.Blocks.Interfaces.RealOutput T5_2
        annotation (Placement(transformation(extent={{100,8},{104,12}})));
      Modelica.Blocks.Interfaces.RealOutput T5_3
        annotation (Placement(transformation(extent={{100,4},{104,8}})));
      Modelica.Blocks.Interfaces.RealOutput T5_4
        annotation (Placement(transformation(extent={{100,0},{104,4}})));
      Modelica.Blocks.Interfaces.RealOutput m6
        annotation (Placement(transformation(extent={{100,-4},{104,0}})));
      Modelica.Blocks.Interfaces.RealOutput T6_1
        annotation (Placement(transformation(extent={{100,-8},{104,-4}})));
      Modelica.Blocks.Interfaces.RealOutput T6_2
        annotation (Placement(transformation(extent={{100,-12},{104,-8}})));
      Modelica.Blocks.Interfaces.RealOutput T6_3
        annotation (Placement(transformation(extent={{100,-16},{104,-12}})));
      Modelica.Blocks.Interfaces.RealOutput T6_4
        annotation (Placement(transformation(extent={{100,-20},{104,-16}})));
      Modelica.Blocks.Interfaces.RealOutput m7
        annotation (Placement(transformation(extent={{100,-24},{104,-20}})));
      Modelica.Blocks.Interfaces.RealOutput T7_1
        annotation (Placement(transformation(extent={{100,-28},{104,-24}})));
      Modelica.Blocks.Interfaces.RealOutput T7_2
        annotation (Placement(transformation(extent={{100,-32},{104,-28}})));
      Modelica.Blocks.Interfaces.RealOutput T7_3
        annotation (Placement(transformation(extent={{100,-36},{104,-32}})));
      Modelica.Blocks.Interfaces.RealOutput T7_4
        annotation (Placement(transformation(extent={{100,-40},{104,-36}})));
      Modelica.Blocks.Interfaces.RealOutput m8
        annotation (Placement(transformation(extent={{100,-44},{104,-40}})));
      Modelica.Blocks.Interfaces.RealOutput T8_1
        annotation (Placement(transformation(extent={{100,-48},{104,-44}})));
      Modelica.Blocks.Interfaces.RealOutput T8_2
        annotation (Placement(transformation(extent={{100,-52},{104,-48}})));
      Modelica.Blocks.Interfaces.RealOutput T8_3
        annotation (Placement(transformation(extent={{100,-56},{104,-52}})));
      Modelica.Blocks.Interfaces.RealOutput T8_4
        annotation (Placement(transformation(extent={{100,-60},{104,-56}})));
      Modelica.Blocks.Interfaces.RealOutput m9
        annotation (Placement(transformation(extent={{100,-64},{104,-60}})));
      Modelica.Blocks.Interfaces.RealOutput T9_1
        annotation (Placement(transformation(extent={{100,-68},{104,-64}})));
      Modelica.Blocks.Interfaces.RealOutput T9_2
        annotation (Placement(transformation(extent={{100,-72},{104,-68}})));
      Modelica.Blocks.Interfaces.RealOutput T9_3
        annotation (Placement(transformation(extent={{100,-76},{104,-72}})));
      Modelica.Blocks.Interfaces.RealOutput T9_4
        annotation (Placement(transformation(extent={{100,-80},{104,-76}})));
      Modelica.Blocks.Interfaces.RealOutput m10
        annotation (Placement(transformation(extent={{100,-84},{104,-80}})));
      Modelica.Blocks.Interfaces.RealOutput T10_1
        annotation (Placement(transformation(extent={{100,-88},{104,-84}})));
      Modelica.Blocks.Interfaces.RealOutput T10_2
        annotation (Placement(transformation(extent={{100,-92},{104,-88}})));
      Modelica.Blocks.Interfaces.RealOutput T10_3
        annotation (Placement(transformation(extent={{100,-96},{104,-92}})));
      Modelica.Blocks.Interfaces.RealOutput T10_4
        annotation (Placement(transformation(extent={{100,-100},{104,-96}})));
    protected
      Real mAll[10] = cat(1, m, fill(mUnused, 10 - nIn));
      Real TAll[10, 4] = cat(1, T, fill(TUnused, 10 - nIn, 4));
    equation
      m1 = mAll[1];
      T1_1 = TAll[1, 1];
      T1_2 = TAll[1, 2];
      T1_3 = TAll[1, 3];
      T1_4 = TAll[1, 4];
      m2 = mAll[2];
      T2_1 = TAll[2, 1];
      T2_2 = TAll[2, 2];
      T2_3 = TAll[2, 3];
      T2_4 = TAll[2, 4];
      m3 = mAll[3];
      T3_1 = TAll[3, 1];
      T3_2 = TAll[3, 2];
      T3_3 = TAll[3, 3];
      T3_4 = TAll[3, 4];
      m4 = mAll[4];
      T4_1 = TAll[4, 1];
      T4_2 = TAll[4, 2];
      T4_3 = TAll[4, 3];
      T4_4 = TAll[4, 4];
      m5 = mAll[5];
      T5_1 = TAll[5, 1];
      T5_2 = TAll[5, 2];
      T5_3 = TAll[5, 3];
      T5_4 = TAll[5, 4];
      m6 = mAll[6];
      T6_1 = TAll[6, 1];
      T6_2 = TAll[6, 2];
      T6_3 = TAll[6, 3];
      T6_4 = TAll[6, 4];
      m7 = mAll[7];
      T7_1 = TAll[7, 1];
      T7_2 = TAll[7, 2];
      T7_3 = TAll[7, 3];
      T7_4 = TAll[7, 4];
      m8 = mAll[8];
      T8_1 = TAll[8, 1];
      T8_2 = TAll[8, 2];
      T8_3 = TAll[8, 3];
      T8_4 = TAll[8, 4];
      m9 = mAll[9];
      T9_1 = TAll[9, 1];
      T9_2 = TAll[9, 2];
      T9_3 = TAll[9, 3];
      T9_4 = TAll[9, 4];
      m10 = mAll[10];
      T10_1 = TAll[10, 1];
      T10_2 = TAll[10, 2];
      T10_3 = TAll[10, 3];
      T10_4 = TAll[10, 4];
      annotation (Icon(graphics={
            Line(points={{-100,40},{0,0},{100,90}}, color={0,0,127}),
            Line(points={{-100,-40},{0,0},{100,-90}}, color={0,0,127}, pattern=LinePattern.Dash),
            Text(extent={{-90,-20},{90,-60}}, textString="1..%nIn")}),
        Documentation(info="<html><p>Output order per pipe i: <code>mi, Ti_1 .. Ti_4</code>.
Outputs of pipes <code>nIn+1..10</code> are set to <code>mUnused</code> / <code>TUnused</code>.</p></html>"));
    end DistributePipe10x4;
  end Utilities;

  package FMU "Models prepared for FMU export"
    extends Modelica.Icons.Package;

    model NetworkFMU
      "Network with a fixed interface for FMU export: 10 scalar load inputs, 10 scalar outputs per substation quantity"
      parameter Integer nSub(min=1, max=10) = 2
        "Number of substations (structural, fixed at export)"
        annotation (Evaluate=true);
      parameter Modelica.Units.SI.HeatFlowRate Q_nominal[nSub]=fill(100e3, nSub)
        "Design load of each substation";
      parameter Modelica.Units.SI.Length L[nSub]=fill(300, nSub)
        "Length of each pipe section (one way)";
      parameter Modelica.Units.SI.Time tauQLoa(min=Modelica.Constants.small) = 300
        "Time constant of first-order lag smoothing the load inputs";
      parameter Real fraQLoa_max(min=0) = 1.1
        "Load inputs are limited to [0, fraQLoa_max*Q_nominal]";
      parameter Modelica.Units.SI.Temperature TSupSet_min(displayUnit="degC") = 313.15
        "Lower limit of the supply temperature set point";
      parameter Modelica.Units.SI.Temperature TSupSet_max(displayUnit="degC") = 393.15
        "Upper limit of the supply temperature set point";
      parameter Modelica.Units.SI.Time tauTSupSet(min=Modelica.Constants.small) = 60
        "Time constant of first-order lag smoothing the supply temperature set point";

      Network net(
        final nSub=nSub,
        final Q_nominal=Q_nominal,
        final L=L,
        final nSeg=3)
        annotation (Placement(transformation(extent={{-40,-40},{40,40}})));

      // Inputs
      Modelica.Blocks.Interfaces.RealInput TSupSet(final unit="K", displayUnit="degC", start=343.15)
        "Plant supply temperature set point"
        annotation (Placement(transformation(extent={{-210,140},{-190,160}})));
      Modelica.Blocks.Interfaces.RealInput QLoa1(final unit="W", start=80e3)
        "Load substation 1 (ignored if 1 > nSub)"
        annotation (Placement(transformation(extent={{-210,82},{-190,98}})));
      Modelica.Blocks.Interfaces.RealInput QLoa2(final unit="W", start=80e3)
        "Load substation 2 (ignored if 2 > nSub)"
        annotation (Placement(transformation(extent={{-210,62},{-190,78}})));
      Modelica.Blocks.Interfaces.RealInput QLoa3(final unit="W", start=80e3)
        "Load substation 3 (ignored if 3 > nSub)"
        annotation (Placement(transformation(extent={{-210,42},{-190,58}})));
      Modelica.Blocks.Interfaces.RealInput QLoa4(final unit="W", start=80e3)
        "Load substation 4 (ignored if 4 > nSub)"
        annotation (Placement(transformation(extent={{-210,22},{-190,38}})));
      Modelica.Blocks.Interfaces.RealInput QLoa5(final unit="W", start=80e3)
        "Load substation 5 (ignored if 5 > nSub)"
        annotation (Placement(transformation(extent={{-210,2},{-190,18}})));
      Modelica.Blocks.Interfaces.RealInput QLoa6(final unit="W", start=80e3)
        "Load substation 6 (ignored if 6 > nSub)"
        annotation (Placement(transformation(extent={{-210,-18},{-190,-2}})));
      Modelica.Blocks.Interfaces.RealInput QLoa7(final unit="W", start=80e3)
        "Load substation 7 (ignored if 7 > nSub)"
        annotation (Placement(transformation(extent={{-210,-38},{-190,-22}})));
      Modelica.Blocks.Interfaces.RealInput QLoa8(final unit="W", start=80e3)
        "Load substation 8 (ignored if 8 > nSub)"
        annotation (Placement(transformation(extent={{-210,-58},{-190,-42}})));
      Modelica.Blocks.Interfaces.RealInput QLoa9(final unit="W", start=80e3)
        "Load substation 9 (ignored if 9 > nSub)"
        annotation (Placement(transformation(extent={{-210,-78},{-190,-62}})));
      Modelica.Blocks.Interfaces.RealInput QLoa10(final unit="W", start=80e3)
        "Load substation 10 (ignored if 10 > nSub)"
        annotation (Placement(transformation(extent={{-210,-98},{-190,-82}})));

      // Scalar outputs
      Modelica.Blocks.Interfaces.RealOutput QPla_flow(final unit="W") "Heat supplied by the plant"
        annotation (Placement(transformation(extent={{190,175},{210,185}})));
      Modelica.Blocks.Interfaces.RealOutput PPum(final unit="W") "Pump electrical power"
        annotation (Placement(transformation(extent={{190,155},{210,165}})));
      Modelica.Blocks.Interfaces.RealOutput QLos_flow(final unit="W") "Total network heat loss"
        annotation (Placement(transformation(extent={{190,135},{210,145}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPla(final unit="K", displayUnit="degC") "Return temperature arriving at the plant"
        annotation (Placement(transformation(extent={{190,115},{210,125}})));

      // Per-substation outputs (outputs > nSub are 0)
      Modelica.Blocks.Interfaces.RealOutput TSupSub1(final unit="K", displayUnit="degC") "Supply temperature at substation 1"
        annotation (Placement(transformation(extent={{190,91},{210,99}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub2(final unit="K", displayUnit="degC") "Supply temperature at substation 2"
        annotation (Placement(transformation(extent={{190,81},{210,89}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub3(final unit="K", displayUnit="degC") "Supply temperature at substation 3"
        annotation (Placement(transformation(extent={{190,71},{210,79}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub4(final unit="K", displayUnit="degC") "Supply temperature at substation 4"
        annotation (Placement(transformation(extent={{190,61},{210,69}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub5(final unit="K", displayUnit="degC") "Supply temperature at substation 5"
        annotation (Placement(transformation(extent={{190,51},{210,59}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub6(final unit="K", displayUnit="degC") "Supply temperature at substation 6"
        annotation (Placement(transformation(extent={{190,41},{210,49}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub7(final unit="K", displayUnit="degC") "Supply temperature at substation 7"
        annotation (Placement(transformation(extent={{190,31},{210,39}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub8(final unit="K", displayUnit="degC") "Supply temperature at substation 8"
        annotation (Placement(transformation(extent={{190,21},{210,29}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub9(final unit="K", displayUnit="degC") "Supply temperature at substation 9"
        annotation (Placement(transformation(extent={{190,11},{210,19}})));
      Modelica.Blocks.Interfaces.RealOutput TSupSub10(final unit="K", displayUnit="degC") "Supply temperature at substation 10"
        annotation (Placement(transformation(extent={{190,1},{210,9}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub1(final unit="K", displayUnit="degC") "Return temperature leaving substation 1"
        annotation (Placement(transformation(extent={{190,-9},{210,-1}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub2(final unit="K", displayUnit="degC") "Return temperature leaving substation 2"
        annotation (Placement(transformation(extent={{190,-19},{210,-11}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub3(final unit="K", displayUnit="degC") "Return temperature leaving substation 3"
        annotation (Placement(transformation(extent={{190,-29},{210,-21}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub4(final unit="K", displayUnit="degC") "Return temperature leaving substation 4"
        annotation (Placement(transformation(extent={{190,-39},{210,-31}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub5(final unit="K", displayUnit="degC") "Return temperature leaving substation 5"
        annotation (Placement(transformation(extent={{190,-49},{210,-41}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub6(final unit="K", displayUnit="degC") "Return temperature leaving substation 6"
        annotation (Placement(transformation(extent={{190,-59},{210,-51}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub7(final unit="K", displayUnit="degC") "Return temperature leaving substation 7"
        annotation (Placement(transformation(extent={{190,-69},{210,-61}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub8(final unit="K", displayUnit="degC") "Return temperature leaving substation 8"
        annotation (Placement(transformation(extent={{190,-79},{210,-71}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub9(final unit="K", displayUnit="degC") "Return temperature leaving substation 9"
        annotation (Placement(transformation(extent={{190,-89},{210,-81}})));
      Modelica.Blocks.Interfaces.RealOutput TRetSub10(final unit="K", displayUnit="degC") "Return temperature leaving substation 10"
        annotation (Placement(transformation(extent={{190,-99},{210,-91}})));
      Modelica.Blocks.Interfaces.RealOutput mSub1(final unit="kg/s") "Mass flow rate through substation 1"
        annotation (Placement(transformation(extent={{190,-109},{210,-101}})));
      Modelica.Blocks.Interfaces.RealOutput mSub2(final unit="kg/s") "Mass flow rate through substation 2"
        annotation (Placement(transformation(extent={{190,-119},{210,-111}})));
      Modelica.Blocks.Interfaces.RealOutput mSub3(final unit="kg/s") "Mass flow rate through substation 3"
        annotation (Placement(transformation(extent={{190,-129},{210,-121}})));
      Modelica.Blocks.Interfaces.RealOutput mSub4(final unit="kg/s") "Mass flow rate through substation 4"
        annotation (Placement(transformation(extent={{190,-139},{210,-131}})));
      Modelica.Blocks.Interfaces.RealOutput mSub5(final unit="kg/s") "Mass flow rate through substation 5"
        annotation (Placement(transformation(extent={{190,-149},{210,-141}})));
      Modelica.Blocks.Interfaces.RealOutput mSub6(final unit="kg/s") "Mass flow rate through substation 6"
        annotation (Placement(transformation(extent={{190,-159},{210,-151}})));
      Modelica.Blocks.Interfaces.RealOutput mSub7(final unit="kg/s") "Mass flow rate through substation 7"
        annotation (Placement(transformation(extent={{190,-169},{210,-161}})));
      Modelica.Blocks.Interfaces.RealOutput mSub8(final unit="kg/s") "Mass flow rate through substation 8"
        annotation (Placement(transformation(extent={{190,-179},{210,-171}})));
      Modelica.Blocks.Interfaces.RealOutput mSub9(final unit="kg/s") "Mass flow rate through substation 9"
        annotation (Placement(transformation(extent={{190,-189},{210,-181}})));
      Modelica.Blocks.Interfaces.RealOutput mSub10(final unit="kg/s") "Mass flow rate through substation 10"
        annotation (Placement(transformation(extent={{190,-199},{210,-191}})));

      // Per-pipe outputs (3 segments -> 4 temperature points per pipe; pipes > nSub are 0)
      Modelica.Blocks.Interfaces.RealOutput mSupPip1(final unit="kg/s")
        "Mass flow rate, supply pipe 1"
        annotation (Placement(transformation(extent={{196,-214},{204,-210}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip1_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 1"
        annotation (Placement(transformation(extent={{196,-218},{204,-214}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip1_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 1"
        annotation (Placement(transformation(extent={{196,-222},{204,-218}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip1_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 1"
        annotation (Placement(transformation(extent={{196,-226},{204,-222}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip1_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 1"
        annotation (Placement(transformation(extent={{196,-230},{204,-226}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip2(final unit="kg/s")
        "Mass flow rate, supply pipe 2"
        annotation (Placement(transformation(extent={{196,-234},{204,-230}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip2_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 2"
        annotation (Placement(transformation(extent={{196,-238},{204,-234}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip2_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 2"
        annotation (Placement(transformation(extent={{196,-242},{204,-238}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip2_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 2"
        annotation (Placement(transformation(extent={{196,-246},{204,-242}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip2_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 2"
        annotation (Placement(transformation(extent={{196,-250},{204,-246}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip3(final unit="kg/s")
        "Mass flow rate, supply pipe 3"
        annotation (Placement(transformation(extent={{196,-254},{204,-250}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip3_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 3"
        annotation (Placement(transformation(extent={{196,-258},{204,-254}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip3_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 3"
        annotation (Placement(transformation(extent={{196,-262},{204,-258}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip3_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 3"
        annotation (Placement(transformation(extent={{196,-266},{204,-262}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip3_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 3"
        annotation (Placement(transformation(extent={{196,-270},{204,-266}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip4(final unit="kg/s")
        "Mass flow rate, supply pipe 4"
        annotation (Placement(transformation(extent={{196,-274},{204,-270}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip4_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 4"
        annotation (Placement(transformation(extent={{196,-278},{204,-274}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip4_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 4"
        annotation (Placement(transformation(extent={{196,-282},{204,-278}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip4_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 4"
        annotation (Placement(transformation(extent={{196,-286},{204,-282}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip4_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 4"
        annotation (Placement(transformation(extent={{196,-290},{204,-286}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip5(final unit="kg/s")
        "Mass flow rate, supply pipe 5"
        annotation (Placement(transformation(extent={{196,-294},{204,-290}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip5_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 5"
        annotation (Placement(transformation(extent={{196,-298},{204,-294}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip5_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 5"
        annotation (Placement(transformation(extent={{196,-302},{204,-298}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip5_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 5"
        annotation (Placement(transformation(extent={{196,-306},{204,-302}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip5_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 5"
        annotation (Placement(transformation(extent={{196,-310},{204,-306}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip6(final unit="kg/s")
        "Mass flow rate, supply pipe 6"
        annotation (Placement(transformation(extent={{196,-314},{204,-310}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip6_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 6"
        annotation (Placement(transformation(extent={{196,-318},{204,-314}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip6_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 6"
        annotation (Placement(transformation(extent={{196,-322},{204,-318}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip6_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 6"
        annotation (Placement(transformation(extent={{196,-326},{204,-322}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip6_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 6"
        annotation (Placement(transformation(extent={{196,-330},{204,-326}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip7(final unit="kg/s")
        "Mass flow rate, supply pipe 7"
        annotation (Placement(transformation(extent={{196,-334},{204,-330}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip7_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 7"
        annotation (Placement(transformation(extent={{196,-338},{204,-334}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip7_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 7"
        annotation (Placement(transformation(extent={{196,-342},{204,-338}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip7_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 7"
        annotation (Placement(transformation(extent={{196,-346},{204,-342}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip7_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 7"
        annotation (Placement(transformation(extent={{196,-350},{204,-346}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip8(final unit="kg/s")
        "Mass flow rate, supply pipe 8"
        annotation (Placement(transformation(extent={{196,-354},{204,-350}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip8_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 8"
        annotation (Placement(transformation(extent={{196,-358},{204,-354}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip8_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 8"
        annotation (Placement(transformation(extent={{196,-362},{204,-358}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip8_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 8"
        annotation (Placement(transformation(extent={{196,-366},{204,-362}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip8_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 8"
        annotation (Placement(transformation(extent={{196,-370},{204,-366}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip9(final unit="kg/s")
        "Mass flow rate, supply pipe 9"
        annotation (Placement(transformation(extent={{196,-374},{204,-370}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip9_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 9"
        annotation (Placement(transformation(extent={{196,-378},{204,-374}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip9_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 9"
        annotation (Placement(transformation(extent={{196,-382},{204,-378}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip9_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 9"
        annotation (Placement(transformation(extent={{196,-386},{204,-382}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip9_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 9"
        annotation (Placement(transformation(extent={{196,-390},{204,-386}})));
      Modelica.Blocks.Interfaces.RealOutput mSupPip10(final unit="kg/s")
        "Mass flow rate, supply pipe 10"
        annotation (Placement(transformation(extent={{196,-394},{204,-390}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip10_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, supply pipe 10"
        annotation (Placement(transformation(extent={{196,-398},{204,-394}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip10_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, supply pipe 10"
        annotation (Placement(transformation(extent={{196,-402},{204,-398}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip10_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, supply pipe 10"
        annotation (Placement(transformation(extent={{196,-406},{204,-402}})));
      Modelica.Blocks.Interfaces.RealOutput TSupPip10_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, supply pipe 10"
        annotation (Placement(transformation(extent={{196,-410},{204,-406}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip1(final unit="kg/s")
        "Mass flow rate, return pipe 1"
        annotation (Placement(transformation(extent={{196,-414},{204,-410}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip1_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 1"
        annotation (Placement(transformation(extent={{196,-418},{204,-414}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip1_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 1"
        annotation (Placement(transformation(extent={{196,-422},{204,-418}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip1_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 1"
        annotation (Placement(transformation(extent={{196,-426},{204,-422}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip1_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 1"
        annotation (Placement(transformation(extent={{196,-430},{204,-426}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip2(final unit="kg/s")
        "Mass flow rate, return pipe 2"
        annotation (Placement(transformation(extent={{196,-434},{204,-430}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip2_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 2"
        annotation (Placement(transformation(extent={{196,-438},{204,-434}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip2_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 2"
        annotation (Placement(transformation(extent={{196,-442},{204,-438}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip2_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 2"
        annotation (Placement(transformation(extent={{196,-446},{204,-442}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip2_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 2"
        annotation (Placement(transformation(extent={{196,-450},{204,-446}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip3(final unit="kg/s")
        "Mass flow rate, return pipe 3"
        annotation (Placement(transformation(extent={{196,-454},{204,-450}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip3_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 3"
        annotation (Placement(transformation(extent={{196,-458},{204,-454}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip3_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 3"
        annotation (Placement(transformation(extent={{196,-462},{204,-458}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip3_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 3"
        annotation (Placement(transformation(extent={{196,-466},{204,-462}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip3_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 3"
        annotation (Placement(transformation(extent={{196,-470},{204,-466}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip4(final unit="kg/s")
        "Mass flow rate, return pipe 4"
        annotation (Placement(transformation(extent={{196,-474},{204,-470}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip4_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 4"
        annotation (Placement(transformation(extent={{196,-478},{204,-474}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip4_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 4"
        annotation (Placement(transformation(extent={{196,-482},{204,-478}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip4_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 4"
        annotation (Placement(transformation(extent={{196,-486},{204,-482}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip4_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 4"
        annotation (Placement(transformation(extent={{196,-490},{204,-486}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip5(final unit="kg/s")
        "Mass flow rate, return pipe 5"
        annotation (Placement(transformation(extent={{196,-494},{204,-490}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip5_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 5"
        annotation (Placement(transformation(extent={{196,-498},{204,-494}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip5_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 5"
        annotation (Placement(transformation(extent={{196,-502},{204,-498}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip5_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 5"
        annotation (Placement(transformation(extent={{196,-506},{204,-502}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip5_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 5"
        annotation (Placement(transformation(extent={{196,-510},{204,-506}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip6(final unit="kg/s")
        "Mass flow rate, return pipe 6"
        annotation (Placement(transformation(extent={{196,-514},{204,-510}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip6_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 6"
        annotation (Placement(transformation(extent={{196,-518},{204,-514}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip6_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 6"
        annotation (Placement(transformation(extent={{196,-522},{204,-518}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip6_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 6"
        annotation (Placement(transformation(extent={{196,-526},{204,-522}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip6_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 6"
        annotation (Placement(transformation(extent={{196,-530},{204,-526}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip7(final unit="kg/s")
        "Mass flow rate, return pipe 7"
        annotation (Placement(transformation(extent={{196,-534},{204,-530}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip7_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 7"
        annotation (Placement(transformation(extent={{196,-538},{204,-534}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip7_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 7"
        annotation (Placement(transformation(extent={{196,-542},{204,-538}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip7_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 7"
        annotation (Placement(transformation(extent={{196,-546},{204,-542}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip7_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 7"
        annotation (Placement(transformation(extent={{196,-550},{204,-546}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip8(final unit="kg/s")
        "Mass flow rate, return pipe 8"
        annotation (Placement(transformation(extent={{196,-554},{204,-550}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip8_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 8"
        annotation (Placement(transformation(extent={{196,-558},{204,-554}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip8_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 8"
        annotation (Placement(transformation(extent={{196,-562},{204,-558}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip8_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 8"
        annotation (Placement(transformation(extent={{196,-566},{204,-562}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip8_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 8"
        annotation (Placement(transformation(extent={{196,-570},{204,-566}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip9(final unit="kg/s")
        "Mass flow rate, return pipe 9"
        annotation (Placement(transformation(extent={{196,-574},{204,-570}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip9_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 9"
        annotation (Placement(transformation(extent={{196,-578},{204,-574}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip9_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 9"
        annotation (Placement(transformation(extent={{196,-582},{204,-578}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip9_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 9"
        annotation (Placement(transformation(extent={{196,-586},{204,-582}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip9_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 9"
        annotation (Placement(transformation(extent={{196,-590},{204,-586}})));
      Modelica.Blocks.Interfaces.RealOutput mRetPip10(final unit="kg/s")
        "Mass flow rate, return pipe 10"
        annotation (Placement(transformation(extent={{196,-594},{204,-590}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip10_1(final unit="K", displayUnit="degC")
        "Temperature point 1 of 4, return pipe 10"
        annotation (Placement(transformation(extent={{196,-598},{204,-594}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip10_2(final unit="K", displayUnit="degC")
        "Temperature point 2 of 4, return pipe 10"
        annotation (Placement(transformation(extent={{196,-602},{204,-598}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip10_3(final unit="K", displayUnit="degC")
        "Temperature point 3 of 4, return pipe 10"
        annotation (Placement(transformation(extent={{196,-606},{204,-602}})));
      Modelica.Blocks.Interfaces.RealOutput TRetPip10_4(final unit="K", displayUnit="degC")
        "Temperature point 4 of 4, return pipe 10"
        annotation (Placement(transformation(extent={{196,-610},{204,-606}})));
      Utilities.DistributePipe10x4 disPipSup(final nIn=nSub) "Per-pipe outputs, supply pipes"
        annotation (Placement(transformation(extent={{110,-410},{130,-210}})));
      Utilities.DistributePipe10x4 disPipRet(final nIn=nSub) "Per-pipe outputs, return pipes"
        annotation (Placement(transformation(extent={{110,-610},{130,-410}})));
      Utilities.Collect10 colQLoa(
        final nOut=nSub,
        final tau=tauQLoa,
        final uMin=0,
        final uMax=fraQLoa_max*Q_nominal)
        "First nSub load inputs as vector, limited and smoothed"
        annotation (Placement(transformation(extent={{-140,-100},{-100,100}})));
      Modelica.Blocks.Nonlinear.Limiter limTSupSet(
        final uMax=TSupSet_max,
        final uMin=TSupSet_min)
        "Supply temperature set point, limited to a plausible range"
        annotation (Placement(transformation(extent={{-150,140},{-130,160}})));
      Modelica.Blocks.Continuous.FirstOrder filTSupSet(
        final T=tauTSupSet,
        initType=Modelica.Blocks.Types.Init.SteadyState)
        "Supply temperature set point, smoothed"
        annotation (Placement(transformation(extent={{-110,140},{-90,160}})));
      Utilities.Distribute10 disTSup(final nIn=nSub)
        annotation (Placement(transformation(extent={{110,0},{130,100}})));
      Utilities.Distribute10 disTRet(final nIn=nSub)
        annotation (Placement(transformation(extent={{110,-100},{130,0}})));
      Utilities.Distribute10 disMSub(final nIn=nSub)
        annotation (Placement(transformation(extent={{110,-200},{130,-100}})));

    equation
      connect(TSupSet, limTSupSet.u)
        annotation (Line(points={{-200,150},{-152,150}}, color={0,0,127}));
      connect(limTSupSet.y, filTSupSet.u)
        annotation (Line(points={{-129,150},{-112,150}}, color={0,0,127}));
      connect(filTSupSet.y, net.TSupSet)
        annotation (Line(points={{-89,150},{-60,150},{-60,2.4},{-48,2.4}}, color={0,0,127}));
      connect(QLoa1, colQLoa.u1)
        annotation (Line(points={{-200,90},{-144,90}}, color={0,0,127}));
      connect(QLoa2, colQLoa.u2)
        annotation (Line(points={{-200,70},{-144,70}}, color={0,0,127}));
      connect(QLoa3, colQLoa.u3)
        annotation (Line(points={{-200,50},{-144,50}}, color={0,0,127}));
      connect(QLoa4, colQLoa.u4)
        annotation (Line(points={{-200,30},{-144,30}}, color={0,0,127}));
      connect(QLoa5, colQLoa.u5)
        annotation (Line(points={{-200,10},{-144,10}}, color={0,0,127}));
      connect(QLoa6, colQLoa.u6)
        annotation (Line(points={{-200,-10},{-144,-10}}, color={0,0,127}));
      connect(QLoa7, colQLoa.u7)
        annotation (Line(points={{-200,-30},{-144,-30}}, color={0,0,127}));
      connect(QLoa8, colQLoa.u8)
        annotation (Line(points={{-200,-50},{-144,-50}}, color={0,0,127}));
      connect(QLoa9, colQLoa.u9)
        annotation (Line(points={{-200,-70},{-144,-70}}, color={0,0,127}));
      connect(QLoa10, colQLoa.u10)
        annotation (Line(points={{-200,-90},{-144,-90}}, color={0,0,127}));
      connect(colQLoa.y, net.Q_flow)
        annotation (Line(points={{-98,0},{-70,0},{-70,-16},{-48,-16}}, color={0,0,127}));
      connect(net.QPla_flow, QPla_flow)
        annotation (Line(points={{44,14},{56,14},{56,180},{200,180}}, color={0,0,127}));
      connect(net.PPum, PPum)
        annotation (Line(points={{44,8},{60,8},{60,160},{200,160}}, color={0,0,127}));
      connect(net.QLos_flow, QLos_flow)
        annotation (Line(points={{44,2},{64,2},{64,140},{200,140}}, color={0,0,127}));
      connect(net.TRetPla, TRetPla)
        annotation (Line(points={{44,-4},{68,-4},{68,120},{200,120}}, color={0,0,127}));
      connect(net.TSupSub, disTSup.u)
        annotation (Line(points={{44,-18},{80,-18},{80,50},{108,50}}, color={0,0,127}));
      connect(disTSup.y1, TSupSub1)
        annotation (Line(points={{131,95},{200,95}}, color={0,0,127}));
      connect(disTSup.y2, TSupSub2)
        annotation (Line(points={{131,85},{200,85}}, color={0,0,127}));
      connect(disTSup.y3, TSupSub3)
        annotation (Line(points={{131,75},{200,75}}, color={0,0,127}));
      connect(disTSup.y4, TSupSub4)
        annotation (Line(points={{131,65},{200,65}}, color={0,0,127}));
      connect(disTSup.y5, TSupSub5)
        annotation (Line(points={{131,55},{200,55}}, color={0,0,127}));
      connect(disTSup.y6, TSupSub6)
        annotation (Line(points={{131,45},{200,45}}, color={0,0,127}));
      connect(disTSup.y7, TSupSub7)
        annotation (Line(points={{131,35},{200,35}}, color={0,0,127}));
      connect(disTSup.y8, TSupSub8)
        annotation (Line(points={{131,25},{200,25}}, color={0,0,127}));
      connect(disTSup.y9, TSupSub9)
        annotation (Line(points={{131,15},{200,15}}, color={0,0,127}));
      connect(disTSup.y10, TSupSub10)
        annotation (Line(points={{131,5},{200,5}}, color={0,0,127}));
      connect(net.TRetSub, disTRet.u)
        annotation (Line(points={{44,-26},{84,-26},{84,-50},{108,-50}}, color={0,0,127}));
      connect(disTRet.y1, TRetSub1)
        annotation (Line(points={{131,-5},{200,-5}}, color={0,0,127}));
      connect(disTRet.y2, TRetSub2)
        annotation (Line(points={{131,-15},{200,-15}}, color={0,0,127}));
      connect(disTRet.y3, TRetSub3)
        annotation (Line(points={{131,-25},{200,-25}}, color={0,0,127}));
      connect(disTRet.y4, TRetSub4)
        annotation (Line(points={{131,-35},{200,-35}}, color={0,0,127}));
      connect(disTRet.y5, TRetSub5)
        annotation (Line(points={{131,-45},{200,-45}}, color={0,0,127}));
      connect(disTRet.y6, TRetSub6)
        annotation (Line(points={{131,-55},{200,-55}}, color={0,0,127}));
      connect(disTRet.y7, TRetSub7)
        annotation (Line(points={{131,-65},{200,-65}}, color={0,0,127}));
      connect(disTRet.y8, TRetSub8)
        annotation (Line(points={{131,-75},{200,-75}}, color={0,0,127}));
      connect(disTRet.y9, TRetSub9)
        annotation (Line(points={{131,-85},{200,-85}}, color={0,0,127}));
      connect(disTRet.y10, TRetSub10)
        annotation (Line(points={{131,-95},{200,-95}}, color={0,0,127}));
      connect(net.TRetPip, disPipRet.T)
        annotation (Line(points={{8,-44},{8,-550},{108,-550}}, color={0,0,127}));
      connect(net.mRetPip_flow, disPipRet.m)
        annotation (Line(points={{16,-44},{16,-470},{108,-470}}, color={0,0,127}));
      connect(net.TSupPip, disPipSup.T)
        annotation (Line(points={{24,-44},{24,-350},{108,-350}}, color={0,0,127}));
      connect(net.mSupPip_flow, disPipSup.m)
        annotation (Line(points={{32,-44},{32,-270},{108,-270}}, color={0,0,127}));
      connect(disPipSup.m1, mSupPip1)
        annotation (Line(points={{130.2,-212},{200,-212}}, color={0,0,127}));
      connect(disPipSup.T1_1, TSupPip1_1)
        annotation (Line(points={{130.2,-216},{200,-216}}, color={0,0,127}));
      connect(disPipSup.T1_2, TSupPip1_2)
        annotation (Line(points={{130.2,-220},{200,-220}}, color={0,0,127}));
      connect(disPipSup.T1_3, TSupPip1_3)
        annotation (Line(points={{130.2,-224},{200,-224}}, color={0,0,127}));
      connect(disPipSup.T1_4, TSupPip1_4)
        annotation (Line(points={{130.2,-228},{200,-228}}, color={0,0,127}));
      connect(disPipSup.m2, mSupPip2)
        annotation (Line(points={{130.2,-232},{200,-232}}, color={0,0,127}));
      connect(disPipSup.T2_1, TSupPip2_1)
        annotation (Line(points={{130.2,-236},{200,-236}}, color={0,0,127}));
      connect(disPipSup.T2_2, TSupPip2_2)
        annotation (Line(points={{130.2,-240},{200,-240}}, color={0,0,127}));
      connect(disPipSup.T2_3, TSupPip2_3)
        annotation (Line(points={{130.2,-244},{200,-244}}, color={0,0,127}));
      connect(disPipSup.T2_4, TSupPip2_4)
        annotation (Line(points={{130.2,-248},{200,-248}}, color={0,0,127}));
      connect(disPipSup.m3, mSupPip3)
        annotation (Line(points={{130.2,-252},{200,-252}}, color={0,0,127}));
      connect(disPipSup.T3_1, TSupPip3_1)
        annotation (Line(points={{130.2,-256},{200,-256}}, color={0,0,127}));
      connect(disPipSup.T3_2, TSupPip3_2)
        annotation (Line(points={{130.2,-260},{200,-260}}, color={0,0,127}));
      connect(disPipSup.T3_3, TSupPip3_3)
        annotation (Line(points={{130.2,-264},{200,-264}}, color={0,0,127}));
      connect(disPipSup.T3_4, TSupPip3_4)
        annotation (Line(points={{130.2,-268},{200,-268}}, color={0,0,127}));
      connect(disPipSup.m4, mSupPip4)
        annotation (Line(points={{130.2,-272},{200,-272}}, color={0,0,127}));
      connect(disPipSup.T4_1, TSupPip4_1)
        annotation (Line(points={{130.2,-276},{200,-276}}, color={0,0,127}));
      connect(disPipSup.T4_2, TSupPip4_2)
        annotation (Line(points={{130.2,-280},{200,-280}}, color={0,0,127}));
      connect(disPipSup.T4_3, TSupPip4_3)
        annotation (Line(points={{130.2,-284},{200,-284}}, color={0,0,127}));
      connect(disPipSup.T4_4, TSupPip4_4)
        annotation (Line(points={{130.2,-288},{200,-288}}, color={0,0,127}));
      connect(disPipSup.m5, mSupPip5)
        annotation (Line(points={{130.2,-292},{200,-292}}, color={0,0,127}));
      connect(disPipSup.T5_1, TSupPip5_1)
        annotation (Line(points={{130.2,-296},{200,-296}}, color={0,0,127}));
      connect(disPipSup.T5_2, TSupPip5_2)
        annotation (Line(points={{130.2,-300},{200,-300}}, color={0,0,127}));
      connect(disPipSup.T5_3, TSupPip5_3)
        annotation (Line(points={{130.2,-304},{200,-304}}, color={0,0,127}));
      connect(disPipSup.T5_4, TSupPip5_4)
        annotation (Line(points={{130.2,-308},{200,-308}}, color={0,0,127}));
      connect(disPipSup.m6, mSupPip6)
        annotation (Line(points={{130.2,-312},{200,-312}}, color={0,0,127}));
      connect(disPipSup.T6_1, TSupPip6_1)
        annotation (Line(points={{130.2,-316},{200,-316}}, color={0,0,127}));
      connect(disPipSup.T6_2, TSupPip6_2)
        annotation (Line(points={{130.2,-320},{200,-320}}, color={0,0,127}));
      connect(disPipSup.T6_3, TSupPip6_3)
        annotation (Line(points={{130.2,-324},{200,-324}}, color={0,0,127}));
      connect(disPipSup.T6_4, TSupPip6_4)
        annotation (Line(points={{130.2,-328},{200,-328}}, color={0,0,127}));
      connect(disPipSup.m7, mSupPip7)
        annotation (Line(points={{130.2,-332},{200,-332}}, color={0,0,127}));
      connect(disPipSup.T7_1, TSupPip7_1)
        annotation (Line(points={{130.2,-336},{200,-336}}, color={0,0,127}));
      connect(disPipSup.T7_2, TSupPip7_2)
        annotation (Line(points={{130.2,-340},{200,-340}}, color={0,0,127}));
      connect(disPipSup.T7_3, TSupPip7_3)
        annotation (Line(points={{130.2,-344},{200,-344}}, color={0,0,127}));
      connect(disPipSup.T7_4, TSupPip7_4)
        annotation (Line(points={{130.2,-348},{200,-348}}, color={0,0,127}));
      connect(disPipSup.m8, mSupPip8)
        annotation (Line(points={{130.2,-352},{200,-352}}, color={0,0,127}));
      connect(disPipSup.T8_1, TSupPip8_1)
        annotation (Line(points={{130.2,-356},{200,-356}}, color={0,0,127}));
      connect(disPipSup.T8_2, TSupPip8_2)
        annotation (Line(points={{130.2,-360},{200,-360}}, color={0,0,127}));
      connect(disPipSup.T8_3, TSupPip8_3)
        annotation (Line(points={{130.2,-364},{200,-364}}, color={0,0,127}));
      connect(disPipSup.T8_4, TSupPip8_4)
        annotation (Line(points={{130.2,-368},{200,-368}}, color={0,0,127}));
      connect(disPipSup.m9, mSupPip9)
        annotation (Line(points={{130.2,-372},{200,-372}}, color={0,0,127}));
      connect(disPipSup.T9_1, TSupPip9_1)
        annotation (Line(points={{130.2,-376},{200,-376}}, color={0,0,127}));
      connect(disPipSup.T9_2, TSupPip9_2)
        annotation (Line(points={{130.2,-380},{200,-380}}, color={0,0,127}));
      connect(disPipSup.T9_3, TSupPip9_3)
        annotation (Line(points={{130.2,-384},{200,-384}}, color={0,0,127}));
      connect(disPipSup.T9_4, TSupPip9_4)
        annotation (Line(points={{130.2,-388},{200,-388}}, color={0,0,127}));
      connect(disPipSup.m10, mSupPip10)
        annotation (Line(points={{130.2,-392},{200,-392}}, color={0,0,127}));
      connect(disPipSup.T10_1, TSupPip10_1)
        annotation (Line(points={{130.2,-396},{200,-396}}, color={0,0,127}));
      connect(disPipSup.T10_2, TSupPip10_2)
        annotation (Line(points={{130.2,-400},{200,-400}}, color={0,0,127}));
      connect(disPipSup.T10_3, TSupPip10_3)
        annotation (Line(points={{130.2,-404},{200,-404}}, color={0,0,127}));
      connect(disPipSup.T10_4, TSupPip10_4)
        annotation (Line(points={{130.2,-408},{200,-408}}, color={0,0,127}));
      connect(disPipRet.m1, mRetPip1)
        annotation (Line(points={{130.2,-412},{200,-412}}, color={0,0,127}));
      connect(disPipRet.T1_1, TRetPip1_1)
        annotation (Line(points={{130.2,-416},{200,-416}}, color={0,0,127}));
      connect(disPipRet.T1_2, TRetPip1_2)
        annotation (Line(points={{130.2,-420},{200,-420}}, color={0,0,127}));
      connect(disPipRet.T1_3, TRetPip1_3)
        annotation (Line(points={{130.2,-424},{200,-424}}, color={0,0,127}));
      connect(disPipRet.T1_4, TRetPip1_4)
        annotation (Line(points={{130.2,-428},{200,-428}}, color={0,0,127}));
      connect(disPipRet.m2, mRetPip2)
        annotation (Line(points={{130.2,-432},{200,-432}}, color={0,0,127}));
      connect(disPipRet.T2_1, TRetPip2_1)
        annotation (Line(points={{130.2,-436},{200,-436}}, color={0,0,127}));
      connect(disPipRet.T2_2, TRetPip2_2)
        annotation (Line(points={{130.2,-440},{200,-440}}, color={0,0,127}));
      connect(disPipRet.T2_3, TRetPip2_3)
        annotation (Line(points={{130.2,-444},{200,-444}}, color={0,0,127}));
      connect(disPipRet.T2_4, TRetPip2_4)
        annotation (Line(points={{130.2,-448},{200,-448}}, color={0,0,127}));
      connect(disPipRet.m3, mRetPip3)
        annotation (Line(points={{130.2,-452},{200,-452}}, color={0,0,127}));
      connect(disPipRet.T3_1, TRetPip3_1)
        annotation (Line(points={{130.2,-456},{200,-456}}, color={0,0,127}));
      connect(disPipRet.T3_2, TRetPip3_2)
        annotation (Line(points={{130.2,-460},{200,-460}}, color={0,0,127}));
      connect(disPipRet.T3_3, TRetPip3_3)
        annotation (Line(points={{130.2,-464},{200,-464}}, color={0,0,127}));
      connect(disPipRet.T3_4, TRetPip3_4)
        annotation (Line(points={{130.2,-468},{200,-468}}, color={0,0,127}));
      connect(disPipRet.m4, mRetPip4)
        annotation (Line(points={{130.2,-472},{200,-472}}, color={0,0,127}));
      connect(disPipRet.T4_1, TRetPip4_1)
        annotation (Line(points={{130.2,-476},{200,-476}}, color={0,0,127}));
      connect(disPipRet.T4_2, TRetPip4_2)
        annotation (Line(points={{130.2,-480},{200,-480}}, color={0,0,127}));
      connect(disPipRet.T4_3, TRetPip4_3)
        annotation (Line(points={{130.2,-484},{200,-484}}, color={0,0,127}));
      connect(disPipRet.T4_4, TRetPip4_4)
        annotation (Line(points={{130.2,-488},{200,-488}}, color={0,0,127}));
      connect(disPipRet.m5, mRetPip5)
        annotation (Line(points={{130.2,-492},{200,-492}}, color={0,0,127}));
      connect(disPipRet.T5_1, TRetPip5_1)
        annotation (Line(points={{130.2,-496},{200,-496}}, color={0,0,127}));
      connect(disPipRet.T5_2, TRetPip5_2)
        annotation (Line(points={{130.2,-500},{200,-500}}, color={0,0,127}));
      connect(disPipRet.T5_3, TRetPip5_3)
        annotation (Line(points={{130.2,-504},{200,-504}}, color={0,0,127}));
      connect(disPipRet.T5_4, TRetPip5_4)
        annotation (Line(points={{130.2,-508},{200,-508}}, color={0,0,127}));
      connect(disPipRet.m6, mRetPip6)
        annotation (Line(points={{130.2,-512},{200,-512}}, color={0,0,127}));
      connect(disPipRet.T6_1, TRetPip6_1)
        annotation (Line(points={{130.2,-516},{200,-516}}, color={0,0,127}));
      connect(disPipRet.T6_2, TRetPip6_2)
        annotation (Line(points={{130.2,-520},{200,-520}}, color={0,0,127}));
      connect(disPipRet.T6_3, TRetPip6_3)
        annotation (Line(points={{130.2,-524},{200,-524}}, color={0,0,127}));
      connect(disPipRet.T6_4, TRetPip6_4)
        annotation (Line(points={{130.2,-528},{200,-528}}, color={0,0,127}));
      connect(disPipRet.m7, mRetPip7)
        annotation (Line(points={{130.2,-532},{200,-532}}, color={0,0,127}));
      connect(disPipRet.T7_1, TRetPip7_1)
        annotation (Line(points={{130.2,-536},{200,-536}}, color={0,0,127}));
      connect(disPipRet.T7_2, TRetPip7_2)
        annotation (Line(points={{130.2,-540},{200,-540}}, color={0,0,127}));
      connect(disPipRet.T7_3, TRetPip7_3)
        annotation (Line(points={{130.2,-544},{200,-544}}, color={0,0,127}));
      connect(disPipRet.T7_4, TRetPip7_4)
        annotation (Line(points={{130.2,-548},{200,-548}}, color={0,0,127}));
      connect(disPipRet.m8, mRetPip8)
        annotation (Line(points={{130.2,-552},{200,-552}}, color={0,0,127}));
      connect(disPipRet.T8_1, TRetPip8_1)
        annotation (Line(points={{130.2,-556},{200,-556}}, color={0,0,127}));
      connect(disPipRet.T8_2, TRetPip8_2)
        annotation (Line(points={{130.2,-560},{200,-560}}, color={0,0,127}));
      connect(disPipRet.T8_3, TRetPip8_3)
        annotation (Line(points={{130.2,-564},{200,-564}}, color={0,0,127}));
      connect(disPipRet.T8_4, TRetPip8_4)
        annotation (Line(points={{130.2,-568},{200,-568}}, color={0,0,127}));
      connect(disPipRet.m9, mRetPip9)
        annotation (Line(points={{130.2,-572},{200,-572}}, color={0,0,127}));
      connect(disPipRet.T9_1, TRetPip9_1)
        annotation (Line(points={{130.2,-576},{200,-576}}, color={0,0,127}));
      connect(disPipRet.T9_2, TRetPip9_2)
        annotation (Line(points={{130.2,-580},{200,-580}}, color={0,0,127}));
      connect(disPipRet.T9_3, TRetPip9_3)
        annotation (Line(points={{130.2,-584},{200,-584}}, color={0,0,127}));
      connect(disPipRet.T9_4, TRetPip9_4)
        annotation (Line(points={{130.2,-588},{200,-588}}, color={0,0,127}));
      connect(disPipRet.m10, mRetPip10)
        annotation (Line(points={{130.2,-592},{200,-592}}, color={0,0,127}));
      connect(disPipRet.T10_1, TRetPip10_1)
        annotation (Line(points={{130.2,-596},{200,-596}}, color={0,0,127}));
      connect(disPipRet.T10_2, TRetPip10_2)
        annotation (Line(points={{130.2,-600},{200,-600}}, color={0,0,127}));
      connect(disPipRet.T10_3, TRetPip10_3)
        annotation (Line(points={{130.2,-604},{200,-604}}, color={0,0,127}));
      connect(disPipRet.T10_4, TRetPip10_4)
        annotation (Line(points={{130.2,-608},{200,-608}}, color={0,0,127}));
      connect(net.mSub_flow, disMSub.u)
        annotation (Line(points={{44,-34},{76,-34},{76,-150},{108,-150}}, color={0,0,127}));
      connect(disMSub.y1, mSub1)
        annotation (Line(points={{131,-105},{200,-105}}, color={0,0,127}));
      connect(disMSub.y2, mSub2)
        annotation (Line(points={{131,-115},{200,-115}}, color={0,0,127}));
      connect(disMSub.y3, mSub3)
        annotation (Line(points={{131,-125},{200,-125}}, color={0,0,127}));
      connect(disMSub.y4, mSub4)
        annotation (Line(points={{131,-135},{200,-135}}, color={0,0,127}));
      connect(disMSub.y5, mSub5)
        annotation (Line(points={{131,-145},{200,-145}}, color={0,0,127}));
      connect(disMSub.y6, mSub6)
        annotation (Line(points={{131,-155},{200,-155}}, color={0,0,127}));
      connect(disMSub.y7, mSub7)
        annotation (Line(points={{131,-165},{200,-165}}, color={0,0,127}));
      connect(disMSub.y8, mSub8)
        annotation (Line(points={{131,-175},{200,-175}}, color={0,0,127}));
      connect(disMSub.y9, mSub9)
        annotation (Line(points={{131,-185},{200,-185}}, color={0,0,127}));
      connect(disMSub.y10, mSub10)
        annotation (Line(points={{131,-195},{200,-195}}, color={0,0,127}));
      annotation (
        Diagram(coordinateSystem(extent={{-200,-620},{200,200}})),
        Icon(coordinateSystem(extent={{-200,-620},{200,200}}), graphics={
            Rectangle(extent={{-200,200},{200,-620}}, lineColor={0,0,0},
              fillColor={255,255,255}, fillPattern=FillPattern.Solid),
            Text(extent={{-160,60},{160,-60}}, textString="FMU"),
            Text(extent={{-160,-80},{160,-140}}, textString="nSub=%nSub")}),
        Documentation(info="<html>
<p>Top-level model for FMU export with a fixed interface independent of
<code>nSub</code>: inputs <code>TSupSet</code> and <code>QLoa1..QLoa10</code>;
outputs <code>QPla_flow</code>, <code>PPum</code>, <code>QLos_flow</code>,
<code>TRetPla</code> and per substation <code>TSupSubi</code>, <code>TRetSubi</code>,
<code>mSubi</code> (i = 1..10), and per pipe (3 segments each) <code>mSupPipi</code>,
<code>TSupPipi_1..TSupPipi_4</code>, <code>mRetPipi</code>, <code>TRetPipi_1..TRetPipi_4</code>.
Temperature point 1 is the pipe inlet, point 4 the outlet (return pipes flow towards the plant).</p>
<p>Load inputs are limited to <code>[0, fraQLoa_max*Q_nominal]</code> and smoothed by a
first-order lag with time constant <code>tauQLoa</code> (default 300 s, tunable at FMU instantiation).</p>
<p>The supply temperature set point is limited to <code>[TSupSet_min, TSupSet_max]</code>
(default 40 to 120 degC) and smoothed with time constant <code>tauTSupSet</code> (default 60 s).
Values outside this range, e.g. a set point sent in degC instead of K, are clipped.</p>
<p>Only the first <code>nSub</code> load inputs are used; per-substation outputs for
<code>i &gt; nSub</code> are 0. <code>nSub</code> is structural: change it and re-export.
Export this model, not <code>NetworkFMUTest</code>.</p>
</html>"));
    end NetworkFMU;

    model NetworkFMUTest "Test harness for NetworkFMU: feeds all inputs with constants"
      extends Modelica.Icons.Example;

      parameter Integer nSub = 3 "Number of substations" annotation (Evaluate=true);
      NetworkFMU fmuMod(
        nSub=nSub,
        Q_nominal=fill(100e3, nSub),
        L=fill(300, nSub))
        annotation (Placement(transformation(extent={{20,-62},{60,20}})));
      Modelica.Blocks.Sources.Constant TSup(k=273.15 + 70) "Supply temperature set point"
        annotation (Placement(transformation(extent={{-80,60},{-60,80}})));
      Modelica.Blocks.Sources.Constant QLoa[10](k=fill(80e3,10))
        "Loads (entries > nSub are ignored)"
        annotation (Placement(transformation(extent={{-40,-10},{-20,10}})));
      Modelica.Blocks.Sources.Pulse pulse(
        amplitude=30,
        width=100,
        period=15*120,
        nperiod=1,
        offset=0,
        startTime=3600)
        annotation (Placement(transformation(extent={{-80,20},{-60,40}})));
      Modelica.Blocks.Math.Add add
        annotation (Placement(transformation(extent={{-40,40},{-20,60}})));
      Modelica.Blocks.Sources.Pulse pulse1(
        amplitude=-20000,
        width=100,
        period=3600,
        nperiod=1,
        offset=80000,
        startTime=20000)
        annotation (Placement(transformation(extent={{-40,-48},{-20,-28}})));
    equation
      connect(QLoa[1].y, fmuMod.QLoa1)
        annotation (Line(points={{-19,0},{-4,0},{-4,9},{20,9}},    color={0,0,127}));
      connect(QLoa[3].y, fmuMod.QLoa3)
        annotation (Line(points={{-19,0},{-4,0},{-4,5},{20,5}},    color={0,0,127}));
      connect(QLoa[4].y, fmuMod.QLoa4)
        annotation (Line(points={{-19,0},{-4,0},{-4,3},{20,3}},    color={0,0,127}));
      connect(QLoa[5].y, fmuMod.QLoa5)
        annotation (Line(points={{-19,0},{-4,0},{-4,1},{20,1}},    color={0,0,127}));
      connect(QLoa[6].y, fmuMod.QLoa6)
        annotation (Line(points={{-19,0},{-4,0},{-4,-1},{20,-1}},    color={0,0,127}));
      connect(QLoa[7].y, fmuMod.QLoa7)
        annotation (Line(points={{-19,0},{-4,0},{-4,-3},{20,-3}},    color={0,0,127}));
      connect(QLoa[8].y, fmuMod.QLoa8)
        annotation (Line(points={{-19,0},{-4,0},{-4,-5},{20,-5}},    color={0,0,127}));
      connect(QLoa[9].y, fmuMod.QLoa9)
        annotation (Line(points={{-19,0},{-4,0},{-4,-7},{20,-7}},    color={0,0,127}));
      connect(QLoa[10].y, fmuMod.QLoa10)
        annotation (Line(points={{-19,0},{-4,0},{-4,-9},{20,-9}},    color={0,0,127}));
      connect(TSup.y, add.u1) annotation (Line(points={{-59,70},{-50,70},{-50,56},{-42,
              56}}, color={0,0,127}));
      connect(pulse.y, add.u2) annotation (Line(points={{-59,30},{-50,30},{-50,44},{
              -42,44}}, color={0,0,127}));
      connect(add.y, fmuMod.TSupSet) annotation (Line(points={{-19,50},{12,50},{12,15},
              {20,15}}, color={0,0,127}));
      connect(pulse1.y, fmuMod.QLoa2) annotation (Line(points={{-19,-38},{-2,
              -38},{-2,7},{20,7}}, color={0,0,127}));
      annotation (experiment(
          StopTime=43200,
          Tolerance=1e-06,
          __Dymola_Algorithm="Dassl"),
        __Dymola_Commands(file(autoRun=true)="script/plotPipeTemperatures.mos"
          "Plot network data"));
    end NetworkFMUTest;
  end FMU;

  package Examples
    extends Modelica.Icons.ExamplesPackage;

    model ConstantLoads
      "Three-substation network driven by constant loads and a constant supply temperature"
      extends Modelica.Icons.Example;

      parameter Integer nSub=3 "Number of substations" annotation (Evaluate=true);

      Network net(
        nSub=nSub,
        Q_nominal={100e3, 80e3, 150e3},
        L={500, 300, 200})
        annotation (Placement(transformation(extent={{-20,-20},{20,20}})));
      Modelica.Blocks.Sources.Constant TSup(k=273.15 + 70)
        "Supply temperature set point"
        annotation (Placement(transformation(extent={{-60,20},{-40,40}})));
      Modelica.Blocks.Sources.Constant QLoa[nSub](k={80e3, 60e3, 120e3})
        "Loads of the substations"
        annotation (Placement(transformation(extent={{-60,-20},{-40,0}})));
    equation
      connect(TSup.y, net.TSupSet)
        annotation (Line(points={{-39,30},{-30,30},{-30,1.2},{-24,1.2}}, color={0,0,127}));
      connect(QLoa.y, net.Q_flow)
        annotation (Line(points={{-39,-10},{-32,-10},{-32,-8},{-24,-8}}, color={0,0,127}));
      annotation (experiment(StopTime=14400, Tolerance=1e-06,
          __Dymola_Algorithm="Dassl"));
    end ConstantLoads;

    model LowLoadBypass
      "Three-substation network at very low load: the end-of-line bypass should open as the far end cools down"
      extends Modelica.Icons.Example;

      parameter Integer nSub=3 "Number of substations" annotation (Evaluate=true);

      Network net(
        nSub=nSub,
        Q_nominal={100e3, 80e3, 150e3},
        L={500, 300, 200})
        annotation (Placement(transformation(extent={{-20,-20},{20,20}})));
      Modelica.Blocks.Sources.Constant TSup(k=273.15 + 70)
        "Supply temperature set point"
        annotation (Placement(transformation(extent={{-60,20},{-40,40}})));
      Modelica.Blocks.Sources.Constant QLoa[nSub](k={5e3, 5e3, 0})
        "Loads of the substations (very low)"
        annotation (Placement(transformation(extent={{-60,-20},{-40,0}})));
    equation
      connect(TSup.y, net.TSupSet)
        annotation (Line(points={{-39,30},{-30,30},{-30,1.2},{-24,1.2}}, color={0,0,127}));
      connect(QLoa.y, net.Q_flow)
        annotation (Line(points={{-39,-10},{-32,-10},{-32,-8},{-24,-8}}, color={0,0,127}));
      annotation (experiment(StopTime=86400, Tolerance=1e-06,
          __Dymola_Algorithm="Dassl"));
    end LowLoadBypass;
  end Examples;

  annotation (uses(IDEAS(version="4.0.0"), Modelica(version="4.0.0")),
    __Dymola_Commands(file="script/exportNetworkFMU.mos" "Create FMUs"));
end SimpleDH;
