/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * La ventana de inicio de sesión de macOS Catalina, para mint-macos.
 *
 * Reemplaza la lista de usuarios de slick-greeter (la de Unity, en caja) por
 * el diseño de la Mac: el avatar redondo en el centro con el nombre debajo,
 * el campo de contraseña redondeado con la flecha →, la pista a los tres
 * intentos y, abajo, Sleep / Restart / Shut Down (o Cancel, cuando hay varios
 * usuarios y ya se eligió uno). Con varios usuarios, primero la fila de
 * avatares y «Other…».
 *
 * Medidas de las capturas de José (login-screen-monterrey01/02, 1920×1080 a
 * 1x): avatar de 144 px con el borde de arriba 169 px sobre el centro de la
 * pantalla; nombre en negrita a 20 px, partido en dos líneas a unos 200 px;
 * campo de 160×28 a 22 px del nombre; Cancel con un círculo de 35 px blanco
 * al 19 % centrado 97 px sobre el borde de abajo y la etiqueta debajo.
 *
 * Habla con LightDM por las mismas señales que la lista original
 * (show_prompt, show_message, authentication_complete). En --test-mode la
 * contraseña buena es «password», como en el resto de slick-greeter.
 *
 * Copyright (C) 2026 José Alberto de la Cruz Malena. GPL-3, como slick-greeter.
 */

public class LoginMac : Gtk.Overlay
{
    private const int AVATAR = 144;
    private const int AVATAR_FILA = 96;
    private const int ANCHO_CAMPO = 160;
    private const int ALTO_CAMPO = 28;

    private Background background;
    private Gtk.Stack vistas;

    /* Un usuario: avatar, nombre, campo y pista. */
    private Gtk.Box centro;
    private AvatarMac avatar;
    private Gtk.Label nombre;
    private Gtk.Entry clave;
    private Gtk.Label guia;
    private Gtk.Entry? campo_usuario = null;
    private Gtk.Label pista;

    /* Varios usuarios: la fila. */
    private Gtk.Box fila;

    /* Abajo. */
    private Gtk.Box botones_energia;
    private BotonMac boton_cancelar;

    private LightDM.User? usuario = null;
    private bool otro = false;          /* «Other…»: se escribe el nombre */
    private bool hay_varios = false;
    private bool prompt_listo = false;  /* LightDM ya pidió la contraseña */
    private string? pendiente = null;   /* lo que se escribió antes del prompt */
    private int fallos = 0;
    private bool prueba_ok = false;

    public LoginMac (Background background)
    {
        this.background = background;
        cargar_css ();

        vistas = new Gtk.Stack ();
        vistas.transition_type = Gtk.StackTransitionType.CROSSFADE;
        vistas.transition_duration = 200;
        vistas.halign = Gtk.Align.CENTER;
        vistas.valign = Gtk.Align.CENTER;
        vistas.show ();
        add (vistas);

        armar_centro ();
        armar_fila ();
        armar_abajo ();

        SlickGreeter.singleton.show_prompt.connect (prompt_cb);
        SlickGreeter.singleton.show_message.connect (mensaje_cb);
        SlickGreeter.singleton.authentication_complete.connect (completa_cb);

        var usuarios = lista_usuarios ();
        hay_varios = usuarios.length () > 1;
        if (hay_varios)
            mostrar_fila ();
        else if (usuarios.length () == 1)
            elegir (usuarios.nth_data (0));
        else
            elegir_otro ();
    }

    /* ── Armado ──────────────────────────────────────────────────────── */

    private void armar_centro ()
    {
        centro = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        centro.halign = Gtk.Align.CENTER;
        /* El avatar empieza 169 px sobre el centro de la pantalla (Monterey). */
        centro.margin_bottom = 102;

        avatar = new AvatarMac (AVATAR);
        avatar.halign = Gtk.Align.CENTER;
        centro.pack_start (avatar, false, false, 0);

        nombre = new Gtk.Label ("");
        nombre.get_style_context ().add_class ("nombre-mac");
        nombre.justify = Gtk.Justification.CENTER;
        nombre.wrap = true;
        nombre.wrap_mode = Pango.WrapMode.WORD;
        /* La Mac parte el nombre a unos 175 px: «José Alberto de la / Cruz Malena». */
        nombre.max_width_chars = 15;
        nombre.halign = Gtk.Align.CENTER;
        nombre.margin_top = 31;
        centro.pack_start (nombre, false, false, 0);

        clave = new Gtk.Entry ();
        clave.get_style_context ().add_class ("clave-mac");
        clave.visibility = false;
        clave.invisible_char = '•';
        clave.width_chars = 1;  /* si no, GTK pide más ancho que los 160 */
        clave.set_size_request (ANCHO_CAMPO, ALTO_CAMPO);
        clave.halign = Gtk.Align.CENTER;
        clave.max_length = 1024;
        /* «Enter Password» se ve aunque el campo tenga el foco, como en la Mac
         * (GTK3 esconde su placeholder al enfocar). */
        guia = new Gtk.Label ("Enter Password");
        guia.get_style_context ().add_class ("guia-mac");
        guia.halign = Gtk.Align.START;
        guia.valign = Gtk.Align.CENTER;
        guia.margin_start = 14;
        var con_guia = new Gtk.Overlay ();
        con_guia.add (clave);
        con_guia.add_overlay (guia);
        con_guia.set_overlay_pass_through (guia, true);
        con_guia.halign = Gtk.Align.CENTER;
        con_guia.margin_top = 18;
        clave.changed.connect (() => {
            clave.secondary_icon_pixbuf = clave.text.length > 0 ? flecha () : null;
            guia.visible = clave.text.length == 0;
        });
        clave.activate.connect (enviar);
        clave.icon_press.connect ((pos) => {
            if (pos == Gtk.EntryIconPosition.SECONDARY)
                enviar ();
        });
        centro.pack_start (con_guia, false, false, 0);

        pista = new Gtk.Label ("");
        pista.get_style_context ().add_class ("pista-mac");
        pista.wrap = true;
        pista.max_width_chars = 30;
        pista.justify = Gtk.Justification.CENTER;
        pista.margin_top = 10;
        pista.no_show_all = true;
        centro.pack_start (pista, false, false, 0);

        centro.show_all ();
        vistas.add_named (centro, "usuario");
    }

    private void armar_fila ()
    {
        fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 40);
        fila.halign = Gtk.Align.CENTER;
        fila.margin_bottom = 70;
        foreach (var u in lista_usuarios ())
        {
            var usu = u;
            fila.pack_start (tarjeta_fila (usu.image, nombre_de (usu), () => { elegir (usu); }), false, false, 0);
        }
        fila.pack_start (tarjeta_fila (null, "Other…", () => { elegir_otro (); }), false, false, 0);
        fila.show_all ();
        vistas.add_named (fila, "fila");
    }

    private Gtk.Widget tarjeta_fila (string? imagen, string texto, owned Callback al_elegir)
    {
        var boton = new Gtk.Button ();
        boton.get_style_context ().add_class ("usuario-fila-mac");
        boton.relief = Gtk.ReliefStyle.NONE;
        var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        var a = new AvatarMac (AVATAR_FILA);
        a.set_imagen (imagen);
        a.halign = Gtk.Align.CENTER;
        caja.pack_start (a, false, false, 0);
        var l = new Gtk.Label (texto);
        l.get_style_context ().add_class ("nombre-fila-mac");
        l.max_width_chars = 14;
        l.wrap = true;
        l.justify = Gtk.Justification.CENTER;
        caja.pack_start (l, false, false, 0);
        boton.add (caja);
        boton.clicked.connect (() => { al_elegir (); });
        return boton;
    }

    private void armar_abajo ()
    {
        var abajo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        abajo.halign = Gtk.Align.CENTER;
        abajo.valign = Gtk.Align.END;
        /* El círculo va centrado 97 px sobre el borde de abajo (Monterey). */
        abajo.margin_bottom = 55;

        botones_energia = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 48);
        if (LightDM.get_can_suspend ())
            botones_energia.pack_start (new BotonMac ("Sleep", BotonMac.Icono.DORMIR, () => { energia ("suspend"); }), false, false, 0);
        if (LightDM.get_can_restart ())
            botones_energia.pack_start (new BotonMac ("Restart", BotonMac.Icono.REINICIAR, () => { energia ("restart"); }), false, false, 0);
        if (LightDM.get_can_shutdown ())
            botones_energia.pack_start (new BotonMac ("Shut Down", BotonMac.Icono.APAGAR, () => { energia ("shutdown"); }), false, false, 0);
        abajo.pack_start (botones_energia, false, false, 0);

        boton_cancelar = new BotonMac ("Cancel", BotonMac.Icono.CANCELAR, () => { cancelar (); });
        boton_cancelar.no_show_all = true;
        abajo.pack_start (boton_cancelar, false, false, 0);

        abajo.show_all ();
        add_overlay (abajo);
    }

    /* ── Usuarios ────────────────────────────────────────────────────── */

    private List<LightDM.User> lista_usuarios ()
    {
        var lista = new List<LightDM.User> ();
        var ocultos = UGSettings.get_strv (UGSettings.KEY_HIDDEN_USERS);
        foreach (var u in LightDM.UserList.get_instance ().users)
        {
            if (u.name in ocultos)
                continue;
            lista.append (u);
        }
        return lista;
    }

    private static string nombre_de (LightDM.User u)
    {
        return (u.real_name != null && u.real_name != "") ? u.real_name : u.name;
    }

    private void mostrar_fila ()
    {
        SlickGreeter.singleton.cancel_authentication ();
        usuario = null;
        otro = false;
        vistas.set_visible_child_name ("fila");
        botones_energia.show ();
        boton_cancelar.hide ();
    }

    private void elegir (LightDM.User u)
    {
        usuario = u;
        otro = false;
        nombre.label = nombre_de (u);
        /* En prueba la foto puede venir de afuera (la de AccountsService la pone
         * el instalador, y el greeter de prueba corre como otro usuario). */
        var foto = SlickGreeter.singleton.test_mode ? Environment.get_variable ("SLICK_GREETER_MAC_AVATAR") : null;
        avatar.set_imagen (foto ?? u.image);
        quitar_campo_usuario ();
        empezar ();
    }

    private void elegir_otro ()
    {
        usuario = null;
        otro = true;
        nombre.label = "";
        avatar.set_imagen (null);
        if (campo_usuario == null)
        {
            campo_usuario = new Gtk.Entry ();
            campo_usuario.get_style_context ().add_class ("clave-mac");
            campo_usuario.placeholder_text = "Name";
            campo_usuario.width_chars = 1;
            campo_usuario.set_size_request (ANCHO_CAMPO, ALTO_CAMPO);
            campo_usuario.halign = Gtk.Align.CENTER;
            campo_usuario.margin_top = 31;
            campo_usuario.activate.connect (() => { clave.grab_focus (); });
            centro.pack_start (campo_usuario, false, false, 0);
            centro.reorder_child (campo_usuario, 2);
            campo_usuario.show ();
        }
        nombre.hide ();
        empezar ();
        campo_usuario.grab_focus ();
    }

    private void quitar_campo_usuario ()
    {
        if (campo_usuario != null)
        {
            campo_usuario.destroy ();
            campo_usuario = null;
        }
        nombre.show ();
    }

    /* Pide a LightDM el usuario y deja el campo listo. */
    private void empezar ()
    {
        fallos = 0;
        prompt_listo = false;
        pendiente = null;
        pista.hide ();
        clave.text = "";
        guia.visible = true;
        clave.sensitive = true;
        vistas.set_visible_child_name ("usuario");
        botones_energia.visible = !hay_varios;
        boton_cancelar.visible = hay_varios;
        autenticar ();
        clave.grab_focus ();
    }

    private void autenticar ()
    {
        prompt_listo = false;
        if (SlickGreeter.singleton.test_mode)
        {
            prompt_listo = true;
            return;
        }
        SlickGreeter.singleton.cancel_authentication ();
        /* Con «Other…» LightDM pregunta el nombre (login:) y se le contesta
         * con lo que se escriba en Name. */
        SlickGreeter.singleton.authenticate (otro ? null : usuario.name);
    }

    public void cancelar ()
    {
        if (hay_varios)
            mostrar_fila ();
        else
        {
            clave.text = "";
            autenticar ();
        }
    }

    /* ── LightDM ─────────────────────────────────────────────────────── */

    private void enviar ()
    {
        if (!clave.sensitive)
            return;
        clave.sensitive = false;
        if (SlickGreeter.singleton.test_mode)
        {
            prueba_ok = clave.text == "password";
            Idle.add (() => { completa_cb (); return false; });
            return;
        }
        if (!prompt_listo)
        {
            pendiente = clave.text;  /* se manda cuando llegue el prompt */
            return;
        }
        prompt_listo = false;
        SlickGreeter.singleton.respond (clave.text);
    }

    private void prompt_cb (string texto, LightDM.PromptType tipo)
    {
        if (tipo == LightDM.PromptType.QUESTION)
        {
            /* «login:» de Other… */
            var n = campo_usuario != null ? campo_usuario.text : "";
            SlickGreeter.singleton.respond (n);
            return;
        }
        prompt_listo = true;
        if (pendiente != null)
        {
            var p = pendiente;
            pendiente = null;
            prompt_listo = false;
            SlickGreeter.singleton.respond (p);
        }
    }

    private void mensaje_cb (string texto, LightDM.MessageType tipo)
    {
        /* «Your account has expired», etc.: va donde va la pista. */
        pista.label = texto;
        pista.show ();
    }

    private void completa_cb ()
    {
        bool ok = SlickGreeter.singleton.test_mode ? prueba_ok : SlickGreeter.singleton.is_authenticated ();
        if (ok)
        {
            var sesion = (usuario != null && usuario.session != null) ? usuario.session : SlickGreeter.get_default_session ();
            if (!SlickGreeter.singleton.start_session (sesion, background))
            {
                pista.label = "Could not start the session.";
                pista.show ();
                clave.sensitive = true;
                autenticar ();
            }
            return;
        }

        fallos++;
        sacudir ();
        clave.text = "";
        clave.sensitive = true;
        clave.grab_focus ();
        if (fallos >= 3)
            mostrar_pista ();
        autenticar ();
    }

    /* La pista de AccountsService (PasswordHint), como la de la Mac. */
    private void mostrar_pista ()
    {
        var nombre_usuario = usuario != null ? usuario.name : (campo_usuario != null ? campo_usuario.text : null);
        if (nombre_usuario == null || nombre_usuario == "")
            return;
        try
        {
            var bus = Bus.get_sync (BusType.SYSTEM);
            var r = bus.call_sync ("org.freedesktop.Accounts", "/org/freedesktop/Accounts",
                                   "org.freedesktop.Accounts", "FindUserByName",
                                   new Variant ("(s)", nombre_usuario), new VariantType ("(o)"),
                                   DBusCallFlags.NONE, 2000);
            string ruta;
            r.get ("(o)", out ruta);
            var p = bus.call_sync ("org.freedesktop.Accounts", ruta,
                                   "org.freedesktop.DBus.Properties", "Get",
                                   new Variant ("(ss)", "org.freedesktop.Accounts.User", "PasswordHint"),
                                   new VariantType ("(v)"), DBusCallFlags.NONE, 2000);
            Variant v;
            p.get ("(v)", out v);
            var texto = v.get_string ();
            if (texto != null && texto != "")
            {
                pista.label = "Hint: " + texto;
                pista.show ();
            }
        }
        catch (Error e)
        {
            debug ("Sin pista de contraseña: %s", e.message);
        }
    }

    /* El «no» de la Mac: el campo se sacude de lado a lado. */
    private void sacudir ()
    {
        int paso = 0;
        int[] desplazamientos = { 12, -12, 9, -9, 5, -5, 2, -2, 0 };
        Timeout.add (40, () => {
            var d = desplazamientos[paso];
            clave.margin_start = d > 0 ? d * 2 : 0;
            clave.margin_end = d < 0 ? -d * 2 : 0;
            paso++;
            return paso < desplazamientos.length;
        });
    }

    private void energia (string accion)
    {
        if (SlickGreeter.singleton.test_mode)
        {
            debug ("Prueba: %s", accion);
            return;
        }
        try
        {
            switch (accion)
            {
            case "suspend":  LightDM.suspend (); break;
            case "restart":  LightDM.restart (); break;
            case "shutdown": LightDM.shutdown (); break;
            }
        }
        catch (Error e)
        {
            warning ("No se pudo %s: %s", accion, e.message);
        }
    }

    /* ── Dibujos ─────────────────────────────────────────────────────── */

    /* La flecha → en un círculo, a la derecha del campo cuando hay texto. */
    private static Gdk.Pixbuf? flecha ()
    {
        var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, 18, 18);
        var c = new Cairo.Context (s);
        c.set_source_rgba (1, 1, 1, 0.9);
        c.set_line_width (1.2);
        c.arc (9, 9, 7.6, 0, 2 * Math.PI);
        c.stroke ();
        c.set_line_width (1.4);
        c.set_line_cap (Cairo.LineCap.ROUND);
        c.set_line_join (Cairo.LineJoin.ROUND);
        c.move_to (5.2, 9);
        c.line_to (12.6, 9);
        c.move_to (9.6, 6);
        c.line_to (12.6, 9);
        c.line_to (9.6, 12);
        c.stroke ();
        return Gdk.pixbuf_get_from_surface (s, 0, 0, 18, 18);
    }

    private void cargar_css ()
    {
        var css = """
            .nombre-mac {
                font-family: ".SF NS", sans-serif;
                font-weight: bold;
                font-size: 20px;
                color: #ffffff;
                text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
            }
            .nombre-fila-mac {
                font-family: ".SF NS", sans-serif;
                font-weight: bold;
                font-size: 15px;
                color: #ffffff;
                text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
            }
            entry.clave-mac {
                font-family: ".SF NS", sans-serif;
                font-size: 13px;
                min-height: 28px;
                padding: 0 6px 0 13px;
                border-radius: 14px;
                border: none;
                box-shadow: none;
                outline: none;
                background-image: none;
                background-color: rgba(255, 255, 255, 0.42);
                color: #ffffff;
                caret-color: #ffffff;
            }
            entry.clave-mac:focus { box-shadow: none; border: none; }
            entry.clave-mac:disabled { color: rgba(255, 255, 255, 0.6); background-color: rgba(255, 255, 255, 0.30); }
            entry.clave-mac image { color: #ffffff; }
            .guia-mac {
                font-family: ".SF NS", sans-serif;
                font-size: 13px;
                color: rgba(255, 255, 255, 0.62);
            }
            /* La barra de arriba de la Mac no tiene franja: solo el texto. */
            menubar, menubar > menuitem {
                background: none;
                background-color: transparent;
                box-shadow: none;
                border: none;
            }
            menubar, menubar label {
                font-family: ".SF NS", sans-serif;
                font-size: 13px;
                color: #ffffff;
                text-shadow: 0 1px 2px rgba(0, 0, 0, 0.4);
            }
            .pista-mac {
                font-family: ".SF NS", sans-serif;
                font-size: 13px;
                color: rgba(255, 255, 255, 0.85);
                text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
            }
            button.usuario-fila-mac, button.boton-mac {
                background: none;
                border: none;
                box-shadow: none;
                padding: 0;
            }
            .etiqueta-boton-mac {
                font-family: ".SF NS", sans-serif;
                font-weight: bold;
                font-size: 12px;
                color: #ffffff;
                text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
            }
        """;
        try
        {
            var p = new Gtk.CssProvider ();
            p.load_from_data (css, -1);
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), p,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
        }
        catch (Error e)
        {
            warning ("CSS de LoginMac: %s", e.message);
        }
    }
}

/* El avatar redondo. Sin foto, la silueta gris de la Mac. */
public class AvatarMac : Gtk.DrawingArea
{
    private int tam;
    private Gdk.Pixbuf? foto = null;

    public AvatarMac (int tam)
    {
        this.tam = tam;
        set_size_request (tam, tam);
    }

    public void set_imagen (string? ruta)
    {
        foto = null;
        if (ruta != null && ruta != "" && FileUtils.test (ruta, FileTest.EXISTS))
        {
            try
            {
                var p = new Gdk.Pixbuf.from_file (ruta);
                /* Recorte cuadrado al centro y a la medida («cover»). */
                var lado = int.min (p.width, p.height);
                var cuadro = new Gdk.Pixbuf.subpixbuf (p, (p.width - lado) / 2, (p.height - lado) / 2, lado, lado);
                var escala = get_scale_factor ();
                foto = cuadro.scale_simple (tam * escala, tam * escala, Gdk.InterpType.HYPER);
            }
            catch (Error e)
            {
                debug ("Avatar %s: %s", ruta, e.message);
            }
        }
        queue_draw ();
    }

    public override bool draw (Cairo.Context c)
    {
        var r = tam / 2.0;
        c.arc (r, r, r, 0, 2 * Math.PI);
        c.clip ();
        if (foto != null)
        {
            var escala = get_scale_factor ();
            c.save ();
            c.scale (1.0 / escala, 1.0 / escala);
            Gdk.cairo_set_source_pixbuf (c, foto, 0, 0);
            c.paint ();
            c.restore ();
        }
        else
        {
            c.set_source_rgb (0.62, 0.63, 0.66);
            c.paint ();
            c.set_source_rgb (0.89, 0.89, 0.90);
            c.arc (r, tam * 0.38, tam * 0.19, 0, 2 * Math.PI);
            c.fill ();
            c.arc (r, tam * 1.02, tam * 0.40, 0, 2 * Math.PI);
            c.fill ();
        }
        return false;
    }
}

/* Los botones de abajo: un círculo de 35 px blanco al 19 % con su dibujo y la
 * etiqueta debajo. */
public class BotonMac : Gtk.Button
{
    public enum Icono { DORMIR, REINICIAR, APAGAR, CANCELAR }

    private const int TAM = 35;
    private Icono icono;
    private Gtk.DrawingArea dibujo;

    public BotonMac (string texto, Icono icono, owned Callback al_pulsar)
    {
        this.icono = icono;
        get_style_context ().add_class ("boton-mac");
        relief = Gtk.ReliefStyle.NONE;
        can_focus = false;

        var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 9);
        dibujo = new Gtk.DrawingArea ();
        dibujo.set_size_request (TAM, TAM);
        dibujo.halign = Gtk.Align.CENTER;
        dibujo.draw.connect (pintar);
        caja.pack_start (dibujo, false, false, 0);
        var l = new Gtk.Label (texto);
        l.get_style_context ().add_class ("etiqueta-boton-mac");
        caja.pack_start (l, false, false, 0);
        add (caja);
        caja.show_all ();

        clicked.connect (() => { al_pulsar (); });
        enter_notify_event.connect (() => { dibujo.queue_draw (); return false; });
        leave_notify_event.connect (() => { dibujo.queue_draw (); return false; });
    }

    private bool pintar (Gtk.Widget w, Cairo.Context c)
    {
        var r = TAM / 2.0;
        var encima = (get_state_flags () & Gtk.StateFlags.PRELIGHT) != 0;
        c.set_source_rgba (1, 1, 1, encima ? 0.30 : 0.19);
        c.arc (r, r, r, 0, 2 * Math.PI);
        c.fill ();

        c.set_source_rgba (1, 1, 1, 0.95);
        c.set_line_width (1.5);
        c.set_line_cap (Cairo.LineCap.ROUND);
        c.set_line_join (Cairo.LineJoin.ROUND);
        switch (icono)
        {
        case Icono.CANCELAR:
            c.arc (r, r, 8.5, 0, 2 * Math.PI);
            c.stroke ();
            c.move_to (r - 3.2, r - 3.2); c.line_to (r + 3.2, r + 3.2);
            c.move_to (r + 3.2, r - 3.2); c.line_to (r - 3.2, r + 3.2);
            c.stroke ();
            break;
        case Icono.APAGAR:
            c.arc (r, r, 7.5, -Math.PI / 2 + 0.75, 3 * Math.PI / 2 - 0.75);
            c.stroke ();
            c.move_to (r, r - 9); c.line_to (r, r - 1.5);
            c.stroke ();
            break;
        case Icono.REINICIAR:
            c.arc (r, r, 7.5, -Math.PI / 2 + 0.6, 3 * Math.PI / 2 - 0.2);
            c.stroke ();
            /* punta de la flecha arriba, apuntando a la derecha */
            c.move_to (r - 0.5, r - 11); c.line_to (r + 2.6, r - 7.5); c.line_to (r - 0.8, r - 4.6);
            c.stroke ();
            break;
        case Icono.DORMIR:
            /* La luna: un círculo al que se le recorta otro corrido. */
            c.push_group ();
            c.arc (r, r, 7.5, 0, 2 * Math.PI);
            c.fill ();
            c.set_operator (Cairo.Operator.DEST_OUT);
            c.arc (r + 4.2, r - 3.4, 6.4, 0, 2 * Math.PI);
            c.fill ();
            c.pop_group_to_source ();
            c.paint ();
            break;
        }
        return false;
    }
}

public delegate void Callback ();
