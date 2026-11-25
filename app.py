from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from flask import Flask, jsonify, render_template, request
from mysql.connector import Error

from db import get_db_connection

app = Flask(__name__)


@app.route("/", endpoint="landing")
def landing():
    return render_template("landing.html")

RECORD_SELECT_SQL = """
    SELECT
        cr.record_id,
        cr.user_id,
        u.name AS user_name,
        cr.category_id,
        cat.category_name,
        cr.record_date,
        cr.carbon_footprint,
        cr.notes,
        t.transport_id,
        t.mode,
        t.vehicle_type,
        t.distance_km,
        t.fuel_type,
        t.factor_id AS transport_factor_id,
        tf.activity_name AS transport_activity_name,
        f.food_id,
        f.food_type,
        f.quantity,
        f.unit,
        f.factor_id AS food_factor_id,
        ff.activity_name AS food_activity_name,
        e.usage_id,
        e.kwh,
        e.factor_id AS electricity_factor_id,
        ef.activity_name AS electricity_activity_name
    FROM CARBON_RECORD AS cr
    INNER JOIN USERS AS u
            ON cr.user_id = u.user_id
    INNER JOIN CATEGORY AS cat
            ON cr.category_id = cat.category_id
    LEFT JOIN TRANSPORTATION AS t
           ON cr.record_id = t.record_id
    LEFT JOIN EMISSION_FACTOR AS tf
           ON t.factor_id = tf.factor_id
    LEFT JOIN FOOD_CONSUMPTION AS f
           ON cr.record_id = f.record_id
    LEFT JOIN EMISSION_FACTOR AS ff
           ON f.factor_id = ff.factor_id
    LEFT JOIN ELECTRICITY_USAGE AS e
           ON cr.record_id = e.record_id
    LEFT JOIN EMISSION_FACTOR AS ef
           ON e.factor_id = ef.factor_id
"""


def json_safe(value):
    """Convert MySQL Decimal and date values so Flask can return JSON."""
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat(sep=" ", timespec="seconds")
    if isinstance(value, date):
        return value.isoformat()
    return value


def close_db(cursor, connection):
    if cursor is not None:
        cursor.close()
    if connection is not None and connection.is_connected():
        connection.close()


def error_response(message, status_code):
    return jsonify({"error": message}), status_code


def get_connection_or_error():
    connection = get_db_connection()
    if connection is None:
        return None, error_response(
            "Could not connect to the EcoTrack database. "
            "Check that MySQL is running and that DB_PASSWORD in .env is correct.",
            500,
        )
    return connection, None


def parse_int(value, field_name):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None, f"{field_name} must be an integer."
    return number, None


def parse_positive_decimal(value, field_name):
    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None, f"{field_name} must be a number."
    if number <= 0:
        return None, f"{field_name} must be greater than 0."
    return number, None


def parse_date(value, field_name):
    if value is None:
        return None, f"{field_name} is required."
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date(), None
    except ValueError:
        return None, f"{field_name} must be a date in YYYY-MM-DD format."


def format_record(row):
    record = {
        "record_id": row["record_id"],
        "user_id": row["user_id"],
        "user_name": row["user_name"],
        "category_id": row["category_id"],
        "category_name": row["category_name"],
        "record_date": json_safe(row["record_date"]),
        "carbon_footprint": json_safe(row["carbon_footprint"]),
        "notes": row["notes"],
        "activity": None,
    }

    category_name = row["category_name"]
    if category_name == "Transportation" and row["transport_id"] is not None:
        record["activity"] = {
            "transport_id": row["transport_id"],
            "mode": row["mode"],
            "vehicle_type": row["vehicle_type"],
            "distance_km": json_safe(row["distance_km"]),
            "fuel_type": row["fuel_type"],
            "factor_id": row["transport_factor_id"],
            "activity_name": row["transport_activity_name"],
        }
    elif category_name == "Food" and row["food_id"] is not None:
        record["activity"] = {
            "food_id": row["food_id"],
            "food_type": row["food_type"],
            "quantity": json_safe(row["quantity"]),
            "unit": row["unit"],
            "factor_id": row["food_factor_id"],
            "activity_name": row["food_activity_name"],
        }
    elif category_name == "Electricity" and row["usage_id"] is not None:
        record["activity"] = {
            "usage_id": row["usage_id"],
            "kwh": json_safe(row["kwh"]),
            "factor_id": row["electricity_factor_id"],
            "activity_name": row["electricity_activity_name"],
        }

    return record


def fetch_record_row(cursor, record_id):
    cursor.execute(
        RECORD_SELECT_SQL + " WHERE cr.record_id = %s",
        (record_id,),
    )
    return cursor.fetchone()


def fetch_user(cursor, user_id):
    cursor.execute(
        "SELECT user_id, name FROM USERS WHERE user_id = %s",
        (user_id,),
    )
    return cursor.fetchone()


def fetch_category(cursor, category_id):
    cursor.execute(
        """
        SELECT category_id, category_name
        FROM CATEGORY
        WHERE category_id = %s
        """,
        (category_id,),
    )
    return cursor.fetchone()


def fetch_factor(cursor, factor_id):
    cursor.execute(
        """
        SELECT factor_id, category_id, activity_name, factor_value, unit
        FROM EMISSION_FACTOR
        WHERE factor_id = %s
        """,
        (factor_id,),
    )
    return cursor.fetchone()


def required_text(data, field_name):
    value = data.get(field_name)
    if value is None or str(value).strip() == "":
        return None, f"{field_name} is required."
    return str(value).strip(), None


def optional_text(data, field_name):
    if field_name not in data:
        return None
    value = data.get(field_name)
    if value is None or str(value).strip() == "":
        return None
    return str(value).strip()


def parse_create_activity(data, category_name, factor):
    """Validate subtype fields and return (activity_values, carbon_footprint, error)."""
    if category_name == "Transportation":
        mode, error = required_text(data, "mode")
        if error:
            return None, None, error
        distance_km, error = parse_positive_decimal(data.get("distance_km"), "distance_km")
        if error:
            return None, None, error
        activity = {
            "mode": mode,
            "vehicle_type": optional_text(data, "vehicle_type"),
            "distance_km": distance_km,
            "fuel_type": optional_text(data, "fuel_type"),
            "factor_id": factor["factor_id"],
        }
        footprint = (distance_km * factor["factor_value"]).quantize(Decimal("0.0001"))
        return activity, footprint, None

    if category_name == "Food":
        food_type, error = required_text(data, "food_type")
        if error:
            return None, None, error
        unit, error = required_text(data, "unit")
        if error:
            return None, None, error
        quantity, error = parse_positive_decimal(data.get("quantity"), "quantity")
        if error:
            return None, None, error
        activity = {
            "food_type": food_type,
            "quantity": quantity,
            "unit": unit,
            "factor_id": factor["factor_id"],
        }
        footprint = (quantity * factor["factor_value"]).quantize(Decimal("0.0001"))
        return activity, footprint, None

    if category_name == "Electricity":
        kwh, error = parse_positive_decimal(data.get("kwh"), "kwh")
        if error:
            return None, None, error
        activity = {
            "kwh": kwh,
            "factor_id": factor["factor_id"],
        }
        footprint = (kwh * factor["factor_value"]).quantize(Decimal("0.0001"))
        return activity, footprint, None

    return None, None, (
        "This category is not one of Transportation, Food, or Electricity."
    )


def insert_activity(cursor, record_id, category_name, activity):
    if category_name == "Transportation":
        cursor.execute(
            """
            INSERT INTO TRANSPORTATION
                (record_id, mode, vehicle_type, distance_km, fuel_type, factor_id)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (
                record_id,
                activity["mode"],
                activity["vehicle_type"],
                activity["distance_km"],
                activity["fuel_type"],
                activity["factor_id"],
            ),
        )
        return

    if category_name == "Food":
        cursor.execute(
            """
            INSERT INTO FOOD_CONSUMPTION
                (record_id, food_type, quantity, unit, factor_id)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                record_id,
                activity["food_type"],
                activity["quantity"],
                activity["unit"],
                activity["factor_id"],
            ),
        )
        return

    cursor.execute(
        """
        INSERT INTO ELECTRICITY_USAGE (record_id, kwh, factor_id)
        VALUES (%s, %s, %s)
        """,
        (record_id, activity["kwh"], activity["factor_id"]),
    )


def update_activity(cursor, record_id, category_name, activity):
    if category_name == "Transportation":
        cursor.execute(
            """
            UPDATE TRANSPORTATION
               SET mode = %s,
                   vehicle_type = %s,
                   distance_km = %s,
                   fuel_type = %s,
                   factor_id = %s
             WHERE record_id = %s
            """,
            (
                activity["mode"],
                activity["vehicle_type"],
                activity["distance_km"],
                activity["fuel_type"],
                activity["factor_id"],
                record_id,
            ),
        )
        return

    if category_name == "Food":
        cursor.execute(
            """
            UPDATE FOOD_CONSUMPTION
               SET food_type = %s,
                   quantity = %s,
                   unit = %s,
                   factor_id = %s
             WHERE record_id = %s
            """,
            (
                activity["food_type"],
                activity["quantity"],
                activity["unit"],
                activity["factor_id"],
                record_id,
            ),
        )
        return

    cursor.execute(
        """
        UPDATE ELECTRICITY_USAGE
           SET kwh = %s,
               factor_id = %s
         WHERE record_id = %s
        """,
        (activity["kwh"], activity["factor_id"], record_id),
    )


def current_activity_payload(record):
    """Turn a formatted record into the same field names used by POST/PUT."""
    activity = record.get("activity") or {}
    payload = {"factor_id": activity.get("factor_id")}
    category_name = record["category_name"]
    if category_name == "Transportation":
        payload.update(
            {
                "mode": activity.get("mode"),
                "vehicle_type": activity.get("vehicle_type"),
                "distance_km": activity.get("distance_km"),
                "fuel_type": activity.get("fuel_type"),
            }
        )
    elif category_name == "Food":
        payload.update(
            {
                "food_type": activity.get("food_type"),
                "quantity": activity.get("quantity"),
                "unit": activity.get("unit"),
            }
        )
    elif category_name == "Electricity":
        payload["kwh"] = activity.get("kwh")
    return payload


@app.route("/")
def home():
    return "Welcome to EcoTrack – Carbon Footprint Tracking Application."


@app.route("/test-db")
def test_db():
    connection = None
    cursor = None

    try:
        connection = get_db_connection()
        if connection is None:
            return (
                "Could not connect to the EcoTrack database. "
                "Check that MySQL is running and that DB_PASSWORD in .env is correct."
            ), 500

        cursor = connection.cursor()

        cursor.execute("SELECT DATABASE()")
        database_name = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM USERS")
        user_count = cursor.fetchone()[0]

        return (
            f"Connected database: {database_name}<br>"
            f"Total registered users: {user_count}"
        )
    except Exception as err:
        return f"Database error: {err}", 500
    finally:
        close_db(cursor, connection)


@app.route("/records", methods=["GET"])
def get_all_records():
    """READ: list every carbon record with category and activity details."""
    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)
        cursor.execute(RECORD_SELECT_SQL + " ORDER BY cr.record_date, cr.record_id")
        rows = cursor.fetchall()
        records = [format_record(row) for row in rows]
        return jsonify({"count": len(records), "records": records})
    except Error as err:
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


@app.route("/records/<int:record_id>", methods=["GET"])
def get_record(record_id):
    """READ: one carbon record by record_id, including JOIN details."""
    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)
        row = fetch_record_row(cursor, record_id)
        if row is None:
            return error_response(
                f"No carbon record found with record_id {record_id}.",
                404,
            )
        return jsonify(format_record(row))
    except Error as err:
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


@app.route("/records", methods=["POST"])
def create_record():
    """CREATE: insert CARBON_RECORD and the matching 1:1 activity row."""
    data = request.get_json(silent=True)
    if not data:
        return error_response(
            "Send a JSON body with the new carbon activity details.",
            400,
        )

    user_id, error = parse_int(data.get("user_id"), "user_id")
    if error:
        return error_response(error, 400)

    category_id, error = parse_int(data.get("category_id"), "category_id")
    if error:
        return error_response(error, 400)

    record_date, error = parse_date(data.get("record_date"), "record_date")
    if error:
        return error_response(error, 400)

    factor_id, error = parse_int(data.get("factor_id"), "factor_id")
    if error:
        return error_response(error, 400)

    notes = optional_text(data, "notes")

    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)

        user = fetch_user(cursor, user_id)
        if user is None:
            return error_response(f"No user found with user_id {user_id}.", 400)

        category = fetch_category(cursor, category_id)
        if category is None:
            return error_response(
                f"No category found with category_id {category_id}.",
                400,
            )

        factor = fetch_factor(cursor, factor_id)
        if factor is None:
            return error_response(f"No emission factor found with factor_id {factor_id}.", 400)

        if factor["category_id"] != category_id:
            return error_response(
                "factor_id must belong to the same category as category_id.",
                400,
            )

        activity, carbon_footprint, error = parse_create_activity(
            data,
            category["category_name"],
            factor,
        )
        if error:
            return error_response(error, 400)

        connection.start_transaction()

        cursor.execute(
            """
            INSERT INTO CARBON_RECORD
                (user_id, category_id, record_date, carbon_footprint, notes)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (user_id, category_id, record_date, carbon_footprint, notes),
        )
        record_id = cursor.lastrowid

        insert_activity(cursor, record_id, category["category_name"], activity)

        connection.commit()

        saved = fetch_record_row(cursor, record_id)
        return jsonify(format_record(saved)), 201
    except Error as err:
        if connection is not None and connection.is_connected():
            connection.rollback()
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


@app.route("/records/<int:record_id>", methods=["PUT"])
def update_record(record_id):
    """UPDATE: change a carbon record and its related activity row."""
    data = request.get_json(silent=True)
    if not data:
        return error_response(
            "Send a JSON body with the fields you want to update.",
            400,
        )

    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)
        existing_row = fetch_record_row(cursor, record_id)
        if existing_row is None:
            return error_response(
                f"No carbon record found with record_id {record_id}.",
                404,
            )

        existing = format_record(existing_row)

        if "category_id" in data:
            new_category_id, error = parse_int(data.get("category_id"), "category_id")
            if error:
                return error_response(error, 400)
            if new_category_id != existing["category_id"]:
                return error_response(
                    "category_id cannot be changed because each record is linked "
                    "1:1 to Transportation, Food, or Electricity.",
                    400,
                )

        user_id = existing["user_id"]
        if "user_id" in data:
            user_id, error = parse_int(data.get("user_id"), "user_id")
            if error:
                return error_response(error, 400)
            if fetch_user(cursor, user_id) is None:
                return error_response(f"No user found with user_id {user_id}.", 400)

        if "record_date" in data:
            record_date, error = parse_date(data.get("record_date"), "record_date")
            if error:
                return error_response(error, 400)
        else:
            record_date = existing["record_date"]

        notes = existing["notes"]
        if "notes" in data:
            notes = optional_text(data, "notes")

        merged_activity = current_activity_payload(existing)
        for field_name in (
            "factor_id",
            "mode",
            "vehicle_type",
            "distance_km",
            "fuel_type",
            "food_type",
            "quantity",
            "unit",
            "kwh",
        ):
            if field_name in data:
                merged_activity[field_name] = data[field_name]

        factor_id, error = parse_int(merged_activity.get("factor_id"), "factor_id")
        if error:
            return error_response(error, 400)

        factor = fetch_factor(cursor, factor_id)
        if factor is None:
            return error_response(f"No emission factor found with factor_id {factor_id}.", 400)

        if factor["category_id"] != existing["category_id"]:
            return error_response(
                "factor_id must belong to the same category as this carbon record.",
                400,
            )

        activity, carbon_footprint, error = parse_create_activity(
            merged_activity,
            existing["category_name"],
            factor,
        )
        if error:
            return error_response(error, 400)

        connection.start_transaction()

        cursor.execute(
            """
            UPDATE CARBON_RECORD
               SET user_id = %s,
                   record_date = %s,
                   carbon_footprint = %s,
                   notes = %s
             WHERE record_id = %s
            """,
            (user_id, record_date, carbon_footprint, notes, record_id),
        )

        update_activity(cursor, record_id, existing["category_name"], activity)

        connection.commit()

        saved = fetch_record_row(cursor, record_id)
        return jsonify(format_record(saved))
    except Error as err:
        if connection is not None and connection.is_connected():
            connection.rollback()
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


@app.route("/records/<int:record_id>", methods=["DELETE"])
def delete_record(record_id):
    """DELETE: remove a carbon record. Related 1:1 activity rows cascade."""
    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)
        existing_row = fetch_record_row(cursor, record_id)
        if existing_row is None:
            return error_response(
                f"No carbon record found with record_id {record_id}.",
                404,
            )

        connection.start_transaction()
        cursor.execute(
            "DELETE FROM CARBON_RECORD WHERE record_id = %s",
            (record_id,),
        )
        connection.commit()

        return jsonify(
            {
                "message": (
                    f"Carbon record {record_id} was deleted. "
                    "Matching TRANSPORTATION, FOOD_CONSUMPTION, ELECTRICITY_USAGE, "
                    "and RECOMMENDATION rows for this record were removed by "
                    "ON DELETE CASCADE."
                ),
                "deleted_record_id": record_id,
            }
        )
    except Error as err:
        if connection is not None and connection.is_connected():
            connection.rollback()
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


def format_kg(value):
    if value is None:
        return "—"
    return f"{float(value):,.4f}"


def to_float(value):
    if value is None:
        return 0.0
    return float(value)


@app.route("/activities")
def activities():
    """Activity management page. Lookups feed the form; CRUD still uses /records."""
    connection = None
    cursor = None
    users = []
    categories = []
    factors = []
    lookup_error = None

    try:
        connection = get_db_connection()
        if connection is None:
            lookup_error = (
                "Could not connect to the EcoTrack database. "
                "Check that MySQL is running and that DB_PASSWORD in .env is correct."
            )
            return render_template(
                "activities.html",
                users=users,
                categories=categories,
                factors=factors,
                lookup_error=lookup_error,
            )

        cursor = connection.cursor(dictionary=True)

        cursor.execute("SELECT user_id, name FROM USERS ORDER BY name")
        users = cursor.fetchall()

        cursor.execute(
            "SELECT category_id, category_name FROM CATEGORY ORDER BY category_name"
        )
        categories = cursor.fetchall()

        cursor.execute(
            """
            SELECT factor_id, category_id, activity_name, factor_value, unit
            FROM EMISSION_FACTOR
            ORDER BY activity_name
            """
        )
        factor_rows = cursor.fetchall()
        factors = [
            {
                "factor_id": row["factor_id"],
                "category_id": row["category_id"],
                "activity_name": row["activity_name"],
                "factor_value": json_safe(row["factor_value"]),
                "unit": row["unit"],
            }
            for row in factor_rows
        ]

        return render_template(
            "activities.html",
            users=users,
            categories=categories,
            factors=factors,
            lookup_error=lookup_error,
        )
    except Error as err:
        return render_template(
            "activities.html",
            users=users,
            categories=categories,
            factors=factors,
            lookup_error=f"Database error: {err}",
        )
    finally:
        close_db(cursor, connection)


@app.route("/dashboard")
def dashboard():
    """READ-only dashboard: overall totals, category view, recent logs, top users."""
    connection = None
    cursor = None

    try:
        connection, error = get_connection_or_error()
        if error:
            return error

        cursor = connection.cursor(dictionary=True)

        cursor.execute("SELECT COUNT(*) AS total_users FROM USERS")
        total_users = cursor.fetchone()["total_users"]

        cursor.execute("SELECT COUNT(*) AS total_records FROM CARBON_RECORD")
        total_records = cursor.fetchone()["total_records"]

        cursor.execute(
            """
            SELECT COALESCE(SUM(carbon_footprint), 0) AS total_emissions_kg_co2e
            FROM CARBON_RECORD
            """
        )
        total_emissions = cursor.fetchone()["total_emissions_kg_co2e"]

        cursor.execute("SELECT GetEmissionLevel(%s) AS emission_level", (total_emissions,))
        emission_level = cursor.fetchone()["emission_level"]

        cursor.execute(
            """
            SELECT AVG(carbon_footprint) AS average_emissions_kg_co2e
            FROM CARBON_RECORD
            """
        )
        average_emissions = cursor.fetchone()["average_emissions_kg_co2e"]

        cursor.execute(
            """
            SELECT
                category_number,
                activity_category,
                total_emissions_kg_co2e,
                average_emissions_kg_co2e,
                carbon_record_count
            FROM CATEGORY_EMISSION_SUMMARY
            ORDER BY total_emissions_kg_co2e DESC
            """
        )
        category_rows = cursor.fetchall()
        categories = []
        chart_labels = []
        chart_values = []
        for row in category_rows:
            total_value = to_float(row["total_emissions_kg_co2e"])
            total_value_sum = to_float(total_emissions)
            percentage = (total_value / total_value_sum * 100) if total_value_sum else 0
            categories.append(
                {
                    "category_id": row["category_number"],
                    "category_name": row["activity_category"],
                    "total_emissions": format_kg(row["total_emissions_kg_co2e"]),
                    "average_emissions": format_kg(row["average_emissions_kg_co2e"]),
                    "record_count": row["carbon_record_count"],
                    "percentage": round(percentage, 1),
                }
            )
            chart_labels.append(row["activity_category"])
            chart_values.append(round(total_value, 4))

        recent_limit = 10
        cursor.execute(
            """
            SELECT
                record_number,
                activity_date,
                user_name,
                activity_category,
                emissions_kg_co2e,
                record_notes
            FROM CARBON_ACTIVITY_DETAILS
            ORDER BY activity_date DESC, record_number DESC
            LIMIT %s
            """,
            (recent_limit,),
        )
        recent_query_rows = cursor.fetchall()
        recent_rows = [
            {
                "record_id": row["record_number"],
                "record_date": json_safe(row["activity_date"]),
                "user_name": row["user_name"],
                "category_name": row["activity_category"],
                "emissions": format_kg(row["emissions_kg_co2e"]),
                "notes": row["record_notes"] if row["record_notes"] else "—",
            }
            for row in recent_query_rows
        ]

        top_user_count = 5
        cursor.callproc("GetTopEmissionUsers", [top_user_count])
        top_user_rows = []
        for result in cursor.stored_results():
            top_user_rows = result.fetchall()

        top_users = []
        for row in top_user_rows:
            if isinstance(row, dict):
                user_number = row["user_number"]
                user_name = row["user_name"]
                email_address = row["email_address"]
                user_total = row["total_emissions_kg_co2e"]
                record_count = row["carbon_record_count"]
            else:
                user_number, user_name, email_address, user_total, record_count = row

            cursor.execute(
                "SELECT GetEmissionLevel(%s) AS emission_level",
                (user_total,),
            )
            level_row = cursor.fetchone()
            if isinstance(level_row, dict):
                level = level_row["emission_level"]
            else:
                level = level_row[0]

            top_users.append(
                {
                    "user_id": user_number,
                    "user_name": user_name,
                    "email": email_address,
                    "total_emissions": format_kg(user_total),
                    "record_count": record_count,
                    "emission_level": level if level else "Unknown",
                }
            )

        return render_template(
            "dashboard.html",
            total_users=total_users,
            total_records=total_records,
            total_emissions=format_kg(total_emissions),
            average_emissions=format_kg(average_emissions),
            emission_level=emission_level if emission_level else "Unknown",
            categories=categories,
            chart_labels=chart_labels,
            chart_values=chart_values,
            recent_rows=recent_rows,
            top_users=top_users,
        )
    except Error as err:
        return error_response(f"Database error: {err}", 500)
    finally:
        close_db(cursor, connection)


if __name__ == "__main__":
    app.run(debug=True)
