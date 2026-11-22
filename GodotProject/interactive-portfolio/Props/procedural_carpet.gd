@tool
class_name ProceduralCarpet extends MeshInstance3D

## How thick a carpet is. Like the old box carpets, its bottom half is under the floor.
const THICKNESS := 0.1
## Texture coordinates per meter. The carpet material's uv1_scale (15 x 20) was set up for the old box carpets, where
## it repeated the texture once a meter on a 5 x 10 m hall carpet. This keeps that size on every carpet.
const UV_PER_METER := Vector2(1.0 / 15.0, 1.0 / 20.0)
## Lightmap texels left empty around each part of the mesh, the same as Room Baker gives the rooms' boxes
const UV2_PADDING := 4.0

## Makes a carpet's mesh from its outline (Carpet.generate_verticies): the top, and a side down from each edge of it.
## There's no bottom, since that's under the floor. It has lightmap UVs (UV2), so Room Baker can bake it.
static func make_mesh(outline: PackedVector3Array) -> ArrayMesh:
	# The sides face out when the outline goes counter-clockwise seen from above (+Z down, like the map), which is
	# how generate_verticies makes it. Geometry2D calls that clockwise, since it takes +Y (here +Z) as up.
	var flat := PackedVector2Array()
	for point in outline: flat.append(Vector2(point.x, point.z))
	if not Geometry2D.is_polygon_clockwise(flat):
		outline.reverse()
		flat.reverse()
	var count := outline.size()
	var top := Rect2(flat[0], Vector2.ZERO) # The top, seen from above
	for point in flat: top = top.expand(point)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array() # In meters, until the size of the whole lightmap layout is known
	var indices := Geometry2D.triangulate_polygon(flat)
	if indices.is_empty(): push_error("Carpet outline %s can't be split into triangles" % outline)

	# The top is the outline itself, split into triangles
	for i in count:
		vertices.append(outline[i])
		normals.append(Vector3.UP)
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		uvs.append(flat[i] * UV_PER_METER)
		uv2s.append(flat[i] - top.position)

	# Each side is a rectangle down from an edge. In the lightmap they go in rows as wide as the top's longest side, with
	# padding after every part (like Godot's own BoxMesh), and the top goes under them. The bake fills the empty texels
	# around each part from a lit neighbor, trying the one below before the one above: with the sides under the top, the
	# texels past the top's bottom edge took the sides' light, and that edge of the carpet came out dark.
	var texel_size : float = ProjectSettings.get_setting("rendering/lightmapping/primitive_meshes/texel_size")
	var padding := UV2_PADDING * texel_size # In meters, like everything in the layout
	var row_width := maxf(top.size.x, top.size.y)
	var spot := Vector2.ZERO # Where the next side goes in the lightmap
	var width := top.size.x + padding
	for i in count:
		var a := outline[i]
		var b := outline[(i + 1) % count]
		var length := a.distance_to(b)
		var along := (b - a) / length
		var out := Vector3(-along.z, 0.0, along.x)
		var down := Vector3.DOWN * THICKNESS
		if spot.x > 0.0 and spot.x + length > row_width: spot = Vector2(0.0, spot.y + THICKNESS + padding)
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([a, b, b + down, a + down]))
		for corner : Vector2 in [Vector2(0.0, 0.0), Vector2(length, 0.0), Vector2(length, THICKNESS), Vector2(0.0, THICKNESS)]:
			normals.append(out)
			tangents.append_array(PackedFloat32Array([along.x, along.y, along.z, 1.0]))
			uvs.append(corner * UV_PER_METER)
			uv2s.append(spot + corner)
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
		spot.x += length + padding
		width = maxf(width, spot.x)

	var below_sides := spot.y + THICKNESS + padding
	for i in count: uv2s[i].y += below_sides # The top, under the sides
	var size := Vector2(width, below_sides + top.size.y + padding) # The whole lightmap layout, in meters
	for i in uv2s.size(): uv2s[i] /= size

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Lightmap texels at the same size as on the rooms' boxes (see PrimitiveMesh's lightmap texel size)
	mesh.lightmap_size_hint = Vector2i((size / texel_size).ceil())
	return mesh
