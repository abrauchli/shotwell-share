using GLib;
using Sqlite;

private struct Item {
	string filename;
	int rating;
	int flags;
	int is_primary_photo;
	int event_id;
	string event;
	string transformations;
	string title;

	public string serialize () {
		return "<item>"
		+ "<filename>%s</filename>".printf (filename)
		+ "<rating>%d</rating>".printf (rating)
		+ "<flags>%d</flags>".printf (flags)
		+ (is_primary_photo == 0 ? "" : "<primary>1</primary>")
		+ "<event_id>%d</event_id>".printf (event_id)
		+ (event           == null ? "" : "<event><![CDATA[%s]]></event>".printf (event))
		+ (transformations == null ? "" : "<transformations><![CDATA[%s]]></transformations>".printf (transformations))
		+ (title           == null ? "" : "<title><![CDATA[%s]]></title>".printf (title))
		+ "</item>\n";
	}
}

public class ShotwellXmlExporter {
	private const string INDEX_FILE_NAME = "shotwell-export.xml";
	string dbfile;
	Database db;
	Gee.Map<string, Gee.List<Item?>> folders = new Gee.HashMap<string, Gee.List<Item?>> ();

	public ShotwellXmlExporter (string dbfile) {
		this.dbfile = dbfile;
	}

	public static int main (string[] args) {
		string dbfile = args[1];
		var e = new ShotwellXmlExporter (dbfile);
		e.export ();
		return 0;
	}

	public void export () {
		if (Database.open (dbfile, out db) != Sqlite.OK)
			error ("Can't open DB file");

		Statement stmt;
		// eventtable: id, name, primary_source_id // (thumb0000001 or vide-000000a)
		// phototable: id, filename, event_id, transformations, flags, rating, title
		// videotable id, filename, event_id, rating, title, flags
		string qry = "SELECT "
		+ "P.id, P.filename, P.rating, P.flags, P.event_id, E.name, P.transformations, P.title, "
		+ "E.primary_source_id "
		+ "FROM PhotoTable P "
		+ "JOIN EventTable E ON P.event_id=E.id";
		if (db.prepare (qry, -1, out stmt, null) != Sqlite.OK) {
			error ("SQL error: %s\n".printf (db.errmsg ()));
		}

		while (stmt.step () == Sqlite.ROW) {
			int photo_id = stmt.column_int (0);
			string filepath = stmt.column_text (1);
			int l = filepath.last_index_of ("/");
			assert (l < filepath.length);
			string file_dir = filepath[0:l+1];
			int rating = stmt.column_int (2);
			int flags = stmt.column_int (3);
			int event_id = stmt.column_int (4);
			string event = stmt.column_text (5);
			string transformations = stmt.column_text (6);
			string title = stmt.column_text (7);
			string primary_source_id = stmt.column_text (8);
			int is_primary_photo = 0;
			primary_source_id.scanf ("thumb%x", ref is_primary_photo);
			is_primary_photo = (is_primary_photo == photo_id ? 1 : 0);

			Item item = Item () {
				filename = filepath[l+1:filepath.length],
				rating = rating,
				flags = flags,
				event_id = event_id,
				event = event,
				transformations = transformations,
				title = title,
				is_primary_photo = is_primary_photo
			};

			Gee.List<Item?> folder = folders.get (file_dir);
			if (folder == null) {
				folder = new Gee.LinkedList<Item?> ();
				folders.set (file_dir, folder);
			}
			folder.add (item);
		}

		// Generate some SID to match up events between xml files
		// Would be even better if we could match up the originating DB
		int micros = new DateTime.now_local ().get_microsecond ();
		Random.set_seed (micros);
		uint sid = Random.next_int ();

		foreach (string path in folders.keys) {
			try {
				var file = File.new_for_path (path + INDEX_FILE_NAME);
				var file_stream = file.replace (null, false, FileCreateFlags.NONE);
				var stream = new DataOutputStream (file_stream);
				stream.put_string ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
				stream.put_string ("<shotwell-export sid=\"%u\">".printf (sid));

				Gee.List<Item?> folder = folders.get(path);
				foreach (Item? i in folder) {
					assert (i != null);
					stream.put_string (i.serialize ());
				}

				stream.put_string ("</shotwell-export>");
			} catch (GLib.Error e) {
				critical (e.message);
			}
		}
	}
}

